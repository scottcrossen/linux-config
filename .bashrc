#!/bin/bash
#author scottcrossen

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

if [ -d $HOME/.bashrc.d ]; then
    for x in $HOME/.bashrc.d/* ; do
        test -f "$x" || continue
        test -x "$x" || continue
        . "$x"
    done
fi
