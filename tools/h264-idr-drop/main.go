// Command h264-idr-drop prepares an H264 stream with the profile of many hardware encoders
// (pic_order_cnt_type = 0, no B-frames) and publishes it via RTSP while dropping
// IDR frames, in order to reproduce DTS extraction failures in MediaMTX.
package main

import (
	"flag"
	"fmt"
	"os"
)

func usage() {
	fmt.Fprintf(os.Stderr, `usage:
  h264-idr-drop convert -in x264.h264 -out sim.h264
  h264-idr-drop publish -in sim.h264 -url rtsp://localhost:8554/upstream [options]

`)
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	var err error

	switch os.Args[1] {
	case "convert":
		fs := flag.NewFlagSet("convert", flag.ExitOnError)
		in := fs.String("in", "", "input Annex-B file, encoded by x264 with -bf 0 -coder cavlc")
		out := fs.String("out", "", "output Annex-B file")
		_ = fs.Parse(os.Args[2:])
		if *in == "" || *out == "" {
			fs.Usage()
			os.Exit(2)
		}
		err = runConvert(*in, *out)

	case "publish":
		fs := flag.NewFlagSet("publish", flag.ExitOnError)
		var conf publishConf
		fs.StringVar(&conf.inPath, "in", "", "input Annex-B file, produced by convert")
		fs.StringVar(&conf.url, "url", "rtsp://localhost:8554/upstream", "RTSP URL to publish to")
		fs.IntVar(&conf.fps, "fps", 25, "frame rate of the input")
		fs.IntVar(&conf.dropIDREvery, "drop-idr-every", 0, "drop every N-th IDR (0 = disabled)")
		fs.IntVar(&conf.dropAfter, "drop-after", 0, "also drop the K frames that follow a dropped IDR")
		fs.BoolVar(&conf.keepParams, "keep-params", false, "keep SPS/PPS of dropped IDRs")
		fs.Float64Var(&conf.rtpLoss, "rtp-loss", 0, "random RTP packet loss, in percent")
		fs.Int64Var(&conf.seed, "seed", 1, "random seed of RTP packet loss")
		fs.DurationVar(&conf.duration, "duration", 0, "stop after this duration (0 = never)")
		_ = fs.Parse(os.Args[2:])
		if conf.inPath == "" {
			fs.Usage()
			os.Exit(2)
		}
		err = runPublish(conf)

	default:
		usage()
		os.Exit(2)
	}

	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
}
