// My Three Minute SC Piece
// by Robert Blatner
// 9/26/17
// *****************************************************************
//
// Its 10/3 now - this is 1.5 work-week's worth of work.
//
// *****************************************************************
//

(
//1/2. *********************** Globals and Server setup ***********************
~tempoClock = TempoClock(70/60).permanent_(true); // memory leak??
~tempo = ~tempoClock.tempo;
~measures = 4; // 4 beats/measure
~recordTime = (~measures * 4) / ~tempo; // seconds
~recordBufferSize = 44100 * ~recordTime / ~tempo * 2;

s = Server.local;

s.options.memSize_(~recordBufferSize); // do i need this? is there way i can get away with smaller local buffer??
//s.options.outDevice_("Scarlett 2i2 USB");
s.options.sampleRate_(44100);
s.newBusAllocators;
ServerBoot.removeAll;
ServerTree.removeAll;
ServerQuit.removeAll;

// Timing/Tempo related math
~beatsPerMeasure = 4;
~secondsPerBeat = ~beatsPerMeasure/~tempo;
~secondsPerMeasure = ~secondsPerBeat * ~beatsPerMeasure;
~beatsPerNoteRatio = [1.45, 2, 0.55] / (~beatsPerMeasure * 2);
~durations = ~beatsPerNoteRatio * ~secondsPerMeasure;
~attack = 0.3;
~release = 0.05;
~sustains = ~durations - (~attack + ~release);

// Buffers for samples
~path = PathName(thisProcess.nowExecutingPath).parentPath++"Samples/";

//3. *********************** define piece-specific functions ***********************
~makeBuffers = {
	~buffers = Dictionary.new;
	PathName(~path).entries.do{
		arg subfolder;
		~buffers.add(
			subfolder.folderName.asSymbol ->
			Array.fill(
				subfolder.entries.size,
				{
					arg i;
					Buffer.read(s, subfolder.entries[i].fullPath);
				}
			)
		);
	};

	// For recording/playback
	~audioSaved = Buffer.alloc(s, ~recordBufferSize, 2).clear;
	~playbackSynth = nil;
};

~makeNodes = {
	s.bind({
		~mainGrp = Group.new;
		~playbackGrp = Group.after(~mainGrp);
	});
};

~makeBusses = {
	~bus = Dictionary.new;
	~bus.add(\reverb -> Bus.audio(s,2));
	~bus.add(\tremolo -> Bus.audio(s,2));
	~bus.add(\pitchshift -> Bus.audio(s,2));
	~bus.add(\record -> Bus.audio(s,2));
	~bus.add(\dopeplayback -> Bus.audio(s,2));
	~bus.add(\delay -> Bus.audio(s,2));
};

~makeEvents = {

	e = Dictionary.new;

	// Instruments
	e.add(\event1 ->
		Pbind(
			\instrument, \bpfbuf,
			\bufnum, Pseq([~buffers[\Guitar][0].bufnum, ~buffers[\Guitar][1].bufnum,~buffers[\Guitar][2].bufnum],inf),
			\dur, Pseq(~durations,inf),
			\atk, exprand(2,3),
			\sus, 1,
			\rel, Pseq([4,5,0.03],inf),
			\mix, 0.3,
			\rq, exprand(0.001,0.002),
			\rate, 1,
			\pan,rrand(-0.5,0.5),
			\amp, Pseq([0.9, 0.9, 0.4],inf),
			\out, [~bus[\reverb], ~bus[\record] ],
			\group, ~mainGrp
		)
	);

	e.add(\event2 ->
		Pbind(
			\instrument, \sawbass,
			\freq,  Prand((Scale.minor.degrees+63).midicps,inf),
			\dur, Prand([0.1,0.2],inf),
			\cutoff, 300,
			\atk, 1,
			\rq, Pseq(Array.fill(6,{arg i; 1 - (i*0.15)}),inf),
			\amp, 0.17,
			\rel, 1,
			\decay, Pseq([0.5,0.25,0.125],inf),
			\out, [0, 1, ~bus[\record] ],
			\group, ~mainGrp
	));

	e.add(\event3 ->
		Pbind(
			\instrument, \bpfsaw,
			\dur, Prand([1,0.5],inf),
			\freq, Prand([1/5,2/3,1,4/3,2,5/2,3,4,6,8],inf),
			\detune, Pwhite(0,0.1),
			\rqmin, 0.005,
			\rqmax, 0.008,
			\cfmin, Prand((Scale.minor.degrees+63).midicps,inf) * Prand([0.5,1,2,4],inf),
			\cfmax, Pkey(\cfmin) * Pwhite(1.008,1.025),
			\atk, 1,
			\sus, 1,
			\rel, 3,
			\amp, 0.5,
			\out, [0, 1,~bus[\record] ],
			\group, ~mainGrp
		)
	);

	e.add(\event4 ->
		Pbind(\instrument, \bass808,
		\amp, 0.15,
		\freq, Pseq([(32).midicps,
			(26).midicps,
			(34).midicps,
		],inf),
		\atk, ~attack,
		\rel, ~release,
		\sus, Pseq(~sustains,inf),
		\dur, Pseq(~durations,inf),
		\out, [0, 1, ~bus[\record]],
		\group, ~mainGrp
	)
	);

	e.add(\play -> {
		{
			e[\event1].play(~tempoClock);
			e[\event2].play(~tempoClock);
			e[\event3].play(~tempoClock);
			e[\event4].play(~tempoClock);
			e[\reverb].value;

		}.fork(~tempoClock);
	}
	);

	// Effects
	e.add(\delay -> {
		Synth(\delay, [\in, ~bus[\delay], \dt, 0.5],
			target:~playbackGrp,
		);
	}
	);

	e.add(\reverb -> {
		Synth(\reverb, [\in, ~bus[\reverb], \mix, 1, \lines, 20, \dt_max, 0.5, \amp, 10],
			target:~playbackGrp,
		);
	}
	);

	// Playback
	e.add(\record-> {
		~audioSaved.clear;
		Synth(\record,
			[\in, ~bus[\record], \bufnum, ~audioSaved.bufnum],
			target:~playbackGrp,
			addAction:'addToTail'
			);
		}
		);

	e.add(\playback -> {
		~playbackSynth = Synth(\dopeplayback,
			[\bufnum, ~audioSaved.bufnum, \time, ~recordTime, \vmix, 0.3, \lpf, 1000, \playrate, 0.75],
			target: ~playbackGrp,
		);
	}
	);

	e.add(\up -> {

		if(~playbackSynth != nil){
			~playbackSynth.get(\playrate, {
				|playrate|
				~playbackSynth.get(\rateChange, {
					|rateChange|
					var newplayrate;

					rateChange = rateChange + 0.05;
					newplayrate = rateChange + playrate;

					if(newplayrate > 1.0){
						rateChange = rateChange - 0.05;
						"Playrate can't go any higher!".postln;
					};

					~playbackSynth.set(\rateChange, rateChange);

				});
			});
		}
		{
			"playbackSynth doesn't exist. Can't increase its play rate.".postln;
		};
	}
	);

	e.add(\down -> {

		if(~playbackSynth != nil){
			~playbackSynth.get(\playrate, {
				|playrate|
				~playbackSynth.get(\rateChange, {
					|rateChange|
					var newplayrate;

					rateChange = rateChange - 0.05;
					newplayrate = rateChange + playrate;

					if(newplayrate < 0.0){
						rateChange = rateChange + 0.05;
						"Playrate can't go any lower!".postln;
					};

					~playbackSynth.set(\rateChange, rateChange);

				});
			});
		}
		{
			"playbackSynth doesn't exist. Can't increase its play rate.".postln;
		};
	}
	);


}; // makeEvents

~playFunc = {
	{
		e[\event1].play(~tempoClock);
		e[\event2].play(~tempoClock);
		e[\event3].play(~tempoClock);
		e[\event4].play(~tempoClock);
		e[\reverb].value;

	}.fork(~tempoClock);
};

~cleanup = {
	s.newBusAllocators;
	ServerBoot.removeAll;
	ServerTree.removeAll;
	ServerQuit.removeAll;
};

//4. *********************** Register Functions with ServerBoot/Quit/Tree ***********************
ServerBoot.add(~makeBuffers);
ServerBoot.add(~makeBusses);
ServerQuit.add(~cleanup);

//5. *********************** Boot Server ***********************
s.waitForBoot( {

	s.sync;

	//6a. *********************** SynthDefs ***********************

	// Reverb
	SynthDef(\reverb, {
		arg in, out=[0,1],
		predelay=0.1,
		revtime=1.8,
		lpf=4500,
		mix=0.15, amp = 1,
		lines=16,dt_min=0.001, dt_max=0.05;
		var dry, wet, temp, sig;

		dry = In.ar(in, 2);
		temp = In.ar(in, 2);
		wet = 0;
		temp = DelayN.ar(temp, 0, 2, predelay);

		lines.do {
			temp = AllpassN.ar(temp, 0.05, {Rand(dt_min, dt_max)} ! 2, revtime);
			temp = LPF.ar(temp, lpf);
			wet = wet+temp;
		};

		sig = XFade2.ar(dry, wet, mix*2-1, amp);
		Out.ar(out, sig);
	}).add;

	// pitchshift
	SynthDef(\pitchshift, {
		arg in, out=[0,1],
		ws=0.2, pr=1, pd=0, td=0,
		mix=0.15, amp = 1;
		var dry,wet,env,sig;

		dry = In.ar(in, 2);
		wet = PitchShift.ar(In.ar(in, 2), ws, pr, pd, td,amp);
		sig = XFade2.ar(dry, wet, mix*2-1);
		Out.ar(out, sig);
	}).add;

	// bpfbuf
	SynthDef(\bpfbuf, {
		arg atk=0, sus=0, rel=3, c1=1, c2=(-1), bufnum, rate=1, spos=0,
		freq=440, rq = 0.01, amp = 1, mix = 1, pan=0, out = [0,1];

		var env, sig;

		env = EnvGen.kr(Env([0,1,1,0],[atk, sus, rel], [c1, 0, c2]), doneAction:2);
		sig = PlayBuf.ar(2, bufnum, rate*BufRateScale.kr(bufnum) * rate, startPos:spos);
		sig = XFade2.ar(sig, BPF.ar(sig, freq, rq, 1/rq.sqrt), mix * 2 - 1);
		sig = Pan2.ar(sig, pan);

		Out.ar(out,sig*env*amp);
	}).add;

	// bpfsaw
	SynthDef(\bpfsaw, {
		arg atk=2, sus=0, rel=3, c1=1, c2=(-1),
		freq=500, detune=0.2, pan=0, cfhzmin=0.1, cfhzmax=0.3,
		cfmin=500, cfmax=2000, rqmin=0.1, rqmax=0.2,
		lsf=200, ldb=0, amp=1, out=0;

		var sig, env;

		env = EnvGen.kr(Env([0,1,1,0],[atk,sus,rel],[c1,0,c2]),doneAction:2);
		sig = Pulse.ar(freq * {LFNoise1.kr(0.5,detune).midiratio}!2);

		sig = BPF.ar(
			sig,
			{LFNoise1.kr(
				LFNoise1.kr(4).exprange(cfhzmin,cfhzmax)
			).exprange(cfmin,cfmax)} ! 2,
			{LFNoise1.kr(0.1).exprange(rqmin,rqmax)} ! 2
		);
		sig = BLowShelf.ar(sig, lsf, 0.5, ldb);
		sig = Balance2.ar(sig[0], sig[1], pan);
		sig = sig * env * amp;
		Out.ar(out, sig);
	}).add;

	// sawbass
	SynthDef(\sawbass,
		{
			arg freq=440, atk=0.001, rel=2, amp=1, phase=0, cutoff=1000, rq=0, out = [0,1],decay=1;
			var sig, env;

			env = EnvGen.kr(Env.new([0,1,0],[atk,rel],[3,-5]),doneAction:2);
			sig = Saw.ar([freq-1,freq+1],amp);

			sig = RLPF.ar(sig, cutoff, rq, amp);

			Out.ar(out, sig * env );
		}
	).add;

	// bass808
	SynthDef(\bass808,
		{
			arg freq, atk=0.01, sus=1, rel=1.5, out=[0,1], amp;
			var sig,env;

			env = EnvGen.kr(Env([0,1,1,0],[atk, sus,rel]),doneAction:2);
			sig = clip2(SinOsc.ar(freq, 3*pi/2,amp),1);
			Out.ar(out,sig*env);

		}
	).add;

	// writetobuf
	SynthDef(\record, {
		arg in, bufnum;
		var inArray, env;
		env = EnvGen.kr(Env([0,1,1,0],[0.1,~recordTime,2],[4,-4]),doneAction:2); // needed to free node after its done
		inArray = In.ar(in*env,2);
		RecordBuf.ar(inArray, bufnum,loop:0,doneAction:2);
	}).add;

	// dopeplayback
	SynthDef(\dopeplayback, {
		arg bufnum, amp = 1, mooglpf = 1000, hpf = 10000,  playrate = 1, rateChange=0,
		vroom = 0.2, vmix=1, vdamp=0.01, out = [0,1];
		var bufsize, length, env, startup, sig;

		startup = playrate / 0.5;
		bufsize = BufFrames.kr(bufnum);
        length = bufsize / BufSampleRate.kr(bufnum); // correct for mono and stereo?

		sig = PlayBuf.ar(2, bufnum, Sweep.ar(Impulse.kr(0), Line.kr(1,0,startup)) + rateChange);
		sig = BMoog.ar(sig, mooglpf);
		sig = FreeVerb.ar(sig, vmix,vroom,vdamp);
		sig = Pan2.ar(sig, SinOsc.ar(2).range(-1,1));

		Out.ar(out, sig  * amp);
	}).add;

	s.sync;

	//6b. *********************** register remaining functions ***********************
	ServerTree.add(~makeNodes);
	ServerTree.add(~makeEvents);
	s.freeAll;

	s.sync;

} );
)

// Instead of MIDI ...
e[\play].value;
e[\record].value;
e[\playback].value;
e[\down].value
e[\up].value
s.plotTree;
ServerTree.removeAll;


