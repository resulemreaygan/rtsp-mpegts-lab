package main

import (
	"fmt"
	"os"
)

// Target stream parameters: pic_order_cnt_type = 0 without B-frames, as produced by many hardware encoders.
const (
	targetLog2MaxFrameNum = 8
	targetLog2MaxPOCLsb   = 16
)

type spsInfo struct {
	log2MaxFrameNum int
}

func hasChromaInfo(profileIdc uint64) bool {
	switch profileIdc {
	case 100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135:
		return true
	}
	return false
}

// rewriteSPS converts a SPS with pic_order_cnt_type = 2 into one with
// pic_order_cnt_type = 0, and sets log2_max_frame_num and gaps_in_frame_num_value_allowed_flag.
func rewriteSPS(nalu []byte) ([]byte, *spsInfo, error) {
	rbsp := emulationPreventionRemove(nalu[1:])
	end, err := stopBitPos(rbsp)
	if err != nil {
		return nil, nil, err
	}

	r := &bitReader{buf: rbsp}
	w := &bitWriter{}

	copyU := func(n int) (uint64, error) {
		v, err2 := r.u(n)
		if err2 != nil {
			return 0, err2
		}
		w.u(v, n)
		return v, nil
	}
	copyUE := func() (uint32, error) {
		v, err2 := r.ue()
		if err2 != nil {
			return 0, err2
		}
		w.ue(v)
		return v, nil
	}

	profileIdc, err := copyU(8)
	if err != nil {
		return nil, nil, err
	}
	if _, err = copyU(16); err != nil { // constraint flags, level_idc
		return nil, nil, err
	}
	if _, err = copyUE(); err != nil { // seq_parameter_set_id
		return nil, nil, err
	}

	if hasChromaInfo(profileIdc) {
		chromaFormatIdc, err2 := copyUE()
		if err2 != nil {
			return nil, nil, err2
		}
		if chromaFormatIdc == 3 {
			if _, err2 = copyU(1); err2 != nil {
				return nil, nil, err2
			}
		}
		for range 2 { // bit_depth_luma_minus8, bit_depth_chroma_minus8
			if _, err2 = copyUE(); err2 != nil {
				return nil, nil, err2
			}
		}
		if _, err2 = copyU(1); err2 != nil { // qpprime_y_zero_transform_bypass_flag
			return nil, nil, err2
		}
		scaling, err2 := copyU(1)
		if err2 != nil {
			return nil, nil, err2
		}
		if scaling != 0 {
			return nil, nil, fmt.Errorf("seq_scaling_matrix_present_flag is not supported")
		}
	}

	log2MaxFrameNumMinus4, err := r.ue()
	if err != nil {
		return nil, nil, err
	}
	w.ue(targetLog2MaxFrameNum - 4)

	pocType, err := r.ue()
	if err != nil {
		return nil, nil, err
	}
	if pocType != 2 {
		return nil, nil, fmt.Errorf("pic_order_cnt_type is %d, expected 2 (encode without B-frames)", pocType)
	}
	w.ue(0)
	w.ue(targetLog2MaxPOCLsb - 4)

	if _, err = copyUE(); err != nil { // max_num_ref_frames
		return nil, nil, err
	}
	if _, err = r.u(1); err != nil { // gaps_in_frame_num_value_allowed_flag
		return nil, nil, err
	}
	w.u(1, 1)

	if err = w.copyUntil(r, end); err != nil {
		return nil, nil, err
	}

	out := append([]byte{nalu[0]}, emulationPreventionAdd(w.finish())...)
	return out, &spsInfo{log2MaxFrameNum: int(log2MaxFrameNumMinus4) + 4}, nil
}

// checkPPS makes sure that slice headers can be rewritten by shifting bits.
func checkPPS(nalu []byte) error {
	r := &bitReader{buf: emulationPreventionRemove(nalu[1:])}
	for range 2 { // pic_parameter_set_id, seq_parameter_set_id
		if _, err := r.ue(); err != nil {
			return err
		}
	}
	entropy, err := r.u(1)
	if err != nil {
		return err
	}
	if entropy != 0 {
		return fmt.Errorf("CABAC is not supported, encode with -coder cavlc")
	}
	bottom, err := r.u(1)
	if err != nil {
		return err
	}
	if bottom != 0 {
		return fmt.Errorf("bottom_field_pic_order_in_frame_present_flag is not supported")
	}
	return nil
}

type sliceHeader struct {
	firstMB  uint32
	frameNum uint32
	poc      uint32
}

// rewriteSlice changes the frame_num length and inserts pic_order_cnt_lsb.
func rewriteSlice(nalu []byte, sps *spsInfo, poc func(firstMB uint32, idr bool) uint32) ([]byte, error) {
	idr := (nalu[0] & 0x1f) == 5
	rbsp := emulationPreventionRemove(nalu[1:])
	end, err := stopBitPos(rbsp)
	if err != nil {
		return nil, err
	}

	r := &bitReader{buf: rbsp}
	w := &bitWriter{}

	firstMB, err := r.ue()
	if err != nil {
		return nil, err
	}
	w.ue(firstMB)

	for range 2 { // slice_type, pic_parameter_set_id
		v, err2 := r.ue()
		if err2 != nil {
			return nil, err2
		}
		w.ue(v)
	}

	frameNum, err := r.u(sps.log2MaxFrameNum)
	if err != nil {
		return nil, err
	}
	w.u(frameNum, targetLog2MaxFrameNum)

	if idr {
		idrPicID, err2 := r.ue()
		if err2 != nil {
			return nil, err2
		}
		w.ue(idrPicID)
	}

	w.u(uint64(poc(firstMB, idr)), targetLog2MaxPOCLsb)

	if err = w.copyUntil(r, end); err != nil {
		return nil, err
	}

	return append([]byte{nalu[0]}, emulationPreventionAdd(w.finish())...), nil
}

func convertStream(in []byte) ([]byte, int, error) {
	var sps *spsInfo
	framesSinceIDR := uint32(0)
	pocValue := uint32(0)
	frames := 0

	pocFunc := func(firstMB uint32, idr bool) uint32 {
		if firstMB == 0 {
			frames++
			if idr {
				framesSinceIDR = 0
			} else {
				framesSinceIDR++
			}
			pocValue = (framesSinceIDR * 2) & ((1 << targetLog2MaxPOCLsb) - 1)
		}
		return pocValue
	}

	nalus := splitAnnexB(in)
	out := make([][]byte, 0, len(nalus))

	for _, nalu := range nalus {
		if len(nalu) == 0 {
			continue
		}

		switch nalu[0] & 0x1f {
		case 7:
			n, info, err := rewriteSPS(nalu)
			if err != nil {
				return nil, 0, fmt.Errorf("SPS: %w", err)
			}
			sps = info
			out = append(out, n)

		case 8:
			if err := checkPPS(nalu); err != nil {
				return nil, 0, fmt.Errorf("PPS: %w", err)
			}
			out = append(out, nalu)

		case 1, 5:
			if sps == nil {
				return nil, 0, fmt.Errorf("slice received before SPS")
			}
			n, err := rewriteSlice(nalu, sps, pocFunc)
			if err != nil {
				return nil, 0, fmt.Errorf("slice: %w", err)
			}
			out = append(out, n)

		default:
			out = append(out, nalu)
		}
	}

	return joinAnnexB(out), frames, nil
}

func runConvert(inPath string, outPath string) error {
	in, err := os.ReadFile(inPath)
	if err != nil {
		return err
	}

	out, frames, err := convertStream(in)
	if err != nil {
		return err
	}

	err = os.WriteFile(outPath, out, 0o644)
	if err != nil {
		return err
	}

	fmt.Printf("converted %d frames: pic_order_cnt_type 2 -> 0, log2_max_frame_num=%d, log2_max_poc_lsb=%d\n",
		frames, targetLog2MaxFrameNum, targetLog2MaxPOCLsb)
	return nil
}
