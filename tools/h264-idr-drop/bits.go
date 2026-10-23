package main

import (
	"bytes"
	"errors"
	"fmt"
)

var errNotEnoughBits = errors.New("not enough bits")

type bitReader struct {
	buf []byte
	pos int
}

func (r *bitReader) bit() (uint64, error) {
	if r.pos >= len(r.buf)*8 {
		return 0, errNotEnoughBits
	}
	v := (r.buf[r.pos/8] >> (7 - uint(r.pos%8))) & 1
	r.pos++
	return uint64(v), nil
}

func (r *bitReader) u(n int) (uint64, error) {
	var v uint64
	for range n {
		b, err := r.bit()
		if err != nil {
			return 0, err
		}
		v = (v << 1) | b
	}
	return v, nil
}

func (r *bitReader) ue() (uint32, error) {
	zeros := 0
	for {
		b, err := r.bit()
		if err != nil {
			return 0, err
		}
		if b == 1 {
			break
		}
		zeros++
		if zeros > 31 {
			return 0, fmt.Errorf("invalid exp-golomb code")
		}
	}
	v, err := r.u(zeros)
	if err != nil {
		return 0, err
	}
	return uint32((1<<zeros)-1) + uint32(v), nil
}

type bitWriter struct {
	buf []byte
	n   int
}

func (w *bitWriter) bit(v uint64) {
	if w.n%8 == 0 {
		w.buf = append(w.buf, 0)
	}
	if v != 0 {
		w.buf[w.n/8] |= 1 << (7 - uint(w.n%8))
	}
	w.n++
}

func (w *bitWriter) u(v uint64, n int) {
	for i := n - 1; i >= 0; i-- {
		w.bit((v >> uint(i)) & 1)
	}
}

func (w *bitWriter) ue(v uint32) {
	v++
	n := 0
	for t := v; t > 1; t >>= 1 {
		n++
	}
	w.u(0, n)
	w.u(uint64(v), n+1)
}

// stopBitPos returns the position of the rbsp_stop_one_bit.
func stopBitPos(rbsp []byte) (int, error) {
	for i := len(rbsp) - 1; i >= 0; i-- {
		if rbsp[i] != 0 {
			for j := 0; j < 8; j++ {
				if (rbsp[i]>>uint(j))&1 != 0 {
					return i*8 + 7 - j, nil
				}
			}
		}
	}
	return 0, fmt.Errorf("rbsp_stop_one_bit not found")
}

// copyUntil copies bits from r to w until the bit at position end (excluded).
func (w *bitWriter) copyUntil(r *bitReader, end int) error {
	for r.pos < end {
		b, err := r.bit()
		if err != nil {
			return err
		}
		w.bit(b)
	}
	return nil
}

// finish writes rbsp_trailing_bits.
func (w *bitWriter) finish() []byte {
	w.bit(1)
	for w.n%8 != 0 {
		w.bit(0)
	}
	return w.buf
}

func emulationPreventionRemove(in []byte) []byte {
	out := make([]byte, 0, len(in))
	zeros := 0
	for _, b := range in {
		if zeros == 2 && b == 3 {
			zeros = 0
			continue
		}
		out = append(out, b)
		if b == 0 {
			zeros++
		} else {
			zeros = 0
		}
	}
	return out
}

func emulationPreventionAdd(in []byte) []byte {
	out := make([]byte, 0, len(in)+len(in)/64)
	zeros := 0
	for _, b := range in {
		if zeros == 2 && b <= 3 {
			out = append(out, 3)
			zeros = 0
		}
		out = append(out, b)
		if b == 0 {
			zeros++
		} else {
			zeros = 0
		}
	}
	return out
}

// splitAnnexB splits an Annex-B byte stream into NAL units.
func splitAnnexB(buf []byte) [][]byte {
	var nalus [][]byte
	start := -1
	i := 0
	for i+2 < len(buf) {
		if buf[i] == 0 && buf[i+1] == 0 && buf[i+2] == 1 {
			if start >= 0 {
				end := i
				for end > start && buf[end-1] == 0 {
					end--
				}
				nalus = append(nalus, buf[start:end])
			}
			i += 3
			start = i
			continue
		}
		i++
	}
	if start >= 0 && start < len(buf) {
		nalus = append(nalus, bytes.TrimRight(buf[start:], "\x00"))
	}
	return nalus
}

func joinAnnexB(nalus [][]byte) []byte {
	var out []byte
	for _, n := range nalus {
		out = append(out, 0, 0, 0, 1)
		out = append(out, n...)
	}
	return out
}
