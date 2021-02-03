# Playrate
A very short composition in Supercollider. Code is structured as described in [this video](https://youtu.be/P85X1Ut3Hfc), but no MIDI capability.

## To use this script ...
Install Supercollider and the BlackrainUGens from [SC3 Plugins](https://github.com/supercollider/sc3-plugins). In the Supercollider IDE, ctrl + enter is used to execute lines/blocks of code. With the synth server off, execute lines 9-815 (this registers a bunch of stuff to the server, then boots the server). Then, execute line 818 to play the music. Use line 820 to record whatever is played (length of recording is determined by ~measures global variable at line 14). Use lines 821-823 to play the recording back and adjust its play rate.
