# Tilo

Tilo is a Wayland compositor inspired by dwm/dwl.

This is a work in progress. My goal is to write a usable, minimal and lightweight Wayland compositor
that contains the features I'm interested (see [Features](#features) below) and no more for the
moment.

Tilo should be very lightweight, comparable to dwm/dwl in memory consumption and processor usage.

All the code in this repository is hand-written by me, no LLMs used for code generation.

## Features

Tilo has (or should have) the following features:

- 10 tags.
- Tiling, monocle and floating modes, as in dwm with the pertag patch.
- Automatic floating managment as in i3.
- Top status bar, same as in dwm.
- Hide the cursor on idle as in unclutter.
- Minimal status information showing battery percentage, mater volume and date. As in zlstatus, but
  utilizing the wl_event_loop instead of epoll if possible, to avoid having a sepparate process only
  for this.
- Wallpaper, ref swaybg.
- Idle managment, ref swayidle.
- Copy-paste functionality as in dwl.

## Build

zig build --summary all
