#!/bin/bash
# Makes props/lecture-cooling.mp4: a 5-slide narrated lecture on Newton's law of cooling, for
# trying videos as a study tool (Grasp reads the moments, your notes link to times).
# Needs ffmpeg (brew install ffmpeg). Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")"
work=$(mktemp -d)
swift slides.swift
lines=(
  "Welcome back. Today we look at Newton's law of cooling: why a hot drink cools quickly at first, and then more and more slowly."
  "The law says the difference between the drink and the room shrinks exponentially. T of t equals T room, plus T zero minus T room, times e to the minus k t. The constant k sets the pace. For an open paper cup of water, k is about 0.031 per minute."
  "A handy number is the half-life of the temperature difference: the natural log of two, divided by k. With k equal to 0.031, the difference halves about every 22 minutes."
  "Putting a lid on the cup cuts evaporation, which carries away a lot of the heat. With a lid, k drops to about 0.019 per minute, so the drink stays hot much longer."
  "For homework, pour three cups at 90 degrees: one open, one with a lid, and one with ice. Log the temperature every second, fit k for each cup, and compare your values with ours."
)
# Each slide's narration, with a short pause after it; each slide stays up exactly as long.
for i in "${!lines[@]}"; do
  n=$((i + 1))
  say -v Samantha -r 175 -o "$work/a$n.aiff" "${lines[$i]}"
  ffmpeg -loglevel error -y -i "$work/a$n.aiff" -af apad=pad_dur=0.8 -ar 44100 -ac 1 "$work/a$n.wav"
  seconds=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/a$n.wav")
  echo "file '$work/a$n.wav'" >> "$work/audio.txt"
  printf "file '%s'\nduration %s\n" "$PWD/slide$n.png" "$seconds" >> "$work/slides.txt"
  last="$PWD/slide$n.png"
done
echo "file '$last'" >> "$work/slides.txt"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$work/audio.txt" "$work/voice.wav"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$work/slides.txt" -i "$work/voice.wav" \
  -vf "fps=10,format=yuv420p" -c:v libx264 -tune stillimage -crf 28 -c:a aac -b:a 96k -shortest ../lecture-cooling.mp4
rm -f slide*.png
rm -rf "$work"
echo "Wrote props/lecture-cooling.mp4"
