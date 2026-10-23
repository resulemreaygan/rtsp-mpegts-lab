package main

import (
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	"github.com/bluenviron/gortsplib/v5"
	"github.com/bluenviron/gortsplib/v5/pkg/description"
	"github.com/bluenviron/gortsplib/v5/pkg/format"
)

type publishConf struct {
	inPath       string
	url          string
	fps          int
	dropIDREvery int
	dropAfter    int
	keepParams   bool
	rtpLoss      float64
	seed         int64
	duration     time.Duration
}

type accessUnit struct {
	nalus [][]byte
	idr   bool
}

func isSlice(typ byte) bool {
	return typ == 1 || typ == 5
}

func firstMBInSlice(nalu []byte) uint32 {
	r := &bitReader{buf: emulationPreventionRemove(nalu[1:min(len(nalu), 8)])}
	v, err := r.ue()
	if err != nil {
		return 0
	}
	return v
}

// groupAccessUnits groups NAL units into access units.
func groupAccessUnits(nalus [][]byte) []accessUnit {
	var aus []accessUnit
	var cur accessUnit
	curHasSlice := false

	flush := func() {
		if len(cur.nalus) != 0 {
			aus = append(aus, cur)
		}
		cur = accessUnit{}
		curHasSlice = false
	}

	for _, n := range nalus {
		if len(n) == 0 {
			continue
		}
		typ := n[0] & 0x1f

		if isSlice(typ) {
			if curHasSlice && firstMBInSlice(n) == 0 {
				flush()
			}
			curHasSlice = true
			if typ == 5 {
				cur.idr = true
			}
		} else if curHasSlice {
			flush()
		}

		cur.nalus = append(cur.nalus, n)
	}
	flush()

	return aus
}

func findParams(aus []accessUnit) ([]byte, []byte) {
	var sps, pps []byte
	for _, au := range aus {
		for _, n := range au.nalus {
			switch n[0] & 0x1f {
			case 7:
				if sps == nil {
					sps = n
				}
			case 8:
				if pps == nil {
					pps = n
				}
			}
		}
	}
	return sps, pps
}

func withoutSlices(au accessUnit) [][]byte {
	var out [][]byte
	for _, n := range au.nalus {
		switch n[0] & 0x1f {
		case 7, 8:
			out = append(out, n)
		}
	}
	return out
}

func runPublish(conf publishConf) error {
	buf, err := os.ReadFile(conf.inPath)
	if err != nil {
		return err
	}

	aus := groupAccessUnits(splitAnnexB(buf))
	if len(aus) == 0 || !aus[0].idr {
		return fmt.Errorf("input must start with an IDR access unit")
	}

	sps, pps := findParams(aus)
	if sps == nil || pps == nil {
		return fmt.Errorf("SPS or PPS not found")
	}

	forma := &format.H264{
		PayloadTyp:        96,
		PacketizationMode: 1,
		SPS:               sps,
		PPS:               pps,
	}
	desc := &description.Session{
		Medias: []*description.Media{{
			Type:    description.MediaTypeVideo,
			Formats: []format.Format{forma},
		}},
	}

	rtpEnc, err := forma.CreateEncoder()
	if err != nil {
		return err
	}

	proto := gortsplib.ProtocolTCP
	c := gortsplib.Client{Protocol: &proto}
	err = c.StartRecording(conf.url, desc)
	if err != nil {
		return err
	}
	defer c.Close()

	rnd := rand.New(rand.NewSource(conf.seed))
	frameDuration := time.Second / time.Duration(conf.fps)
	ticksPerFrame := int64(90000 / conf.fps)
	randomStart := rnd.Uint32()
	start := time.Now()

	log.Printf("publishing %d access units in loop to %s (drop-idr-every=%d drop-after=%d keep-params=%v rtp-loss=%.3f%%)",
		len(aus), conf.url, conf.dropIDREvery, conf.dropAfter, conf.keepParams, conf.rtpLoss)

	var (
		frame         int64
		idrCount      int
		dropRemaining int
		droppedIDRs   int
		droppedFrames int
		lostPackets   int
		sentPackets   int
		lastReport    = start
	)

	for {
		for _, au := range aus {
			if conf.duration > 0 && time.Since(start) >= conf.duration {
				log.Printf("done: frames=%d droppedIDRs=%d droppedFrames=%d lostRTP=%d/%d",
					frame, droppedIDRs, droppedFrames, lostPackets, sentPackets+lostPackets)
				return nil
			}

			time.Sleep(time.Until(start.Add(time.Duration(frame) * frameDuration)))

			pts := frame * ticksPerFrame
			frame++

			nalus := au.nalus

			switch {
			case au.idr:
				idrCount++
				if conf.dropIDREvery > 0 && idrCount%conf.dropIDREvery == 0 {
					droppedIDRs++
					dropRemaining = conf.dropAfter
					log.Printf("dropping IDR at %.2fs (frame %d)", float64(pts)/90000, frame-1)
					if conf.keepParams {
						nalus = withoutSlices(au)
					} else {
						nalus = nil
					}
				}

			case dropRemaining > 0:
				dropRemaining--
				droppedFrames++
				nalus = nil
			}

			if len(nalus) == 0 {
				continue
			}

			pkts, err := rtpEnc.Encode(nalus)
			if err != nil {
				return err
			}

			for _, pkt := range pkts {
				if conf.rtpLoss > 0 && rnd.Float64()*100 < conf.rtpLoss {
					lostPackets++
					continue
				}
				pkt.Timestamp += randomStart + uint32(pts)
				err = c.WritePacketRTP(desc.Medias[0], pkt)
				if err != nil {
					return err
				}
				sentPackets++
			}

			if time.Since(lastReport) >= 30*time.Second {
				lastReport = time.Now()
				log.Printf("stats: frames=%d droppedIDRs=%d droppedFrames=%d lostRTP=%d/%d",
					frame, droppedIDRs, droppedFrames, lostPackets, sentPackets+lostPackets)
			}
		}
	}
}
