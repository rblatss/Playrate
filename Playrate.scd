// ****************************************************************************
// *                                                                          *
// *                                  Playrate                                *
// *                             by Robert Blatner                            *
// *                                                                          *
// ****************************************************************************


(
//1/2. *********************** Globals and Server setup ***********************
~bpm = 70/60;
~tempoClock = TempoClock(~bpm).permanent_(true); // memory leak??
~tempo = ~tempoClock.tempo;
~measures = 8;
~beatsPerMeasure = 4;
~recordTime = (~measures * ~beatsPerMeasure) / ~tempo; // seconds
~recordBufferSize = 44100 * ~recordTime / ~tempo * 2; // bytes
~secondsPerBeat = ~beatsPerMeasure/~tempo;
~secondsPerMeasure = ~secondsPerBeat * ~beatsPerMeasure;
~beatsPerNoteRatio = [1.45, 2, 0.55] / (~beatsPerMeasure * 2);
~durations = ~beatsPerNoteRatio * ~secondsPerMeasure;
~attack = 0.3;
~release = 0.05;
~sustains = ~durations - (~attack + ~release);

s = Server.local;

s.options.memSize_(~recordBufferSize); // do i need this? is there way i can get away with smaller local buffer??
//s.options.outDevice_("Scarlett 2i2 USB");
s.options.numOutputBusChannels = 8;
s.options.sampleRate_(44100);
s.newBusAllocators;
ServerBoot.removeAll;
ServerTree.removeAll;
ServerQuit.removeAll;

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
		~ctrlSrcGrp = Group.new;
		~mainGrp = Group.after(~ctrlSrcGrp);
		~effectsGrp = Group.after(~mainGrp);
		~playbackGrp = Group.after(~effectsGrp);
	});
};

~makeBusses = {
	~bus = Dictionary.new;

	// Audio
	~bus.add(\reverb -> Bus.audio(s,2));
	~bus.add(\tremolo -> Bus.audio(s,2));
	~bus.add(\pitchshift -> Bus.audio(s,2));
	~bus.add(\dopeplayback -> Bus.audio(s,2));
	~bus.add(\delay -> Bus.audio(s,2));
	~bus.add(\bpf -> Bus.audio(s,2));

	// Controls
	~bus.add(\freqCtrlBus -> Bus.control(s,1));
	~bus.add(\panCtrlBus -> Bus.control(s,1));
};

~makeEvents = {

	e = Dictionary.new;
	~p1_events = Dictionary.new;
	~p2_events = Dictionary.new;
	~p3_events = Dictionary.new;

	// Events
	e.add(\playpart1 -> Task({

		3.do{
			|i|
			e[\stoppart].value(i + 1);
		};

		e[\delay].value;
		e[\reverb].value;
		e[\pitchshift].value(in:~bus[\pitchshift], out:~bus[\delay]);

		s.sync;

		s.makeBundle(s.latency, {
			~p1_events.add(\p1e1 -> Pbind(
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
				\out, ~bus[\pitchshift],
				\group, ~mainGrp
			).play(~tempoClock);
			);

			~p1_events.add(\p1e2 -> Pbind(
				\instrument, \sawbass,
				\freq,  Prand((Scale.minor.degrees+63).midicps,inf),
				\dur, Prand([0.1,0.2],inf),
				\cutoff, 300,
				\atk, 1,
				\rq, Pseq(Array.fill(6,{arg i; 1 - (i*0.15)}),inf),
				\amp, 0.17,
				\rel, 1,
				\decay, Pseq([0.5,0.25,0.125],inf),
				\out, 0,
				\group, ~mainGrp
			).play(~tempoClock);
			);

			~p1_events.add(\p1e3 -> Pbind(
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
				\out, 0,
				\group, ~mainGrp
			).play(~tempoClock);
			);

			~p1_events.add(\p1e4 -> Pbind(\instrument, \bass808,
				\amp, 0.15,
				\freq, Pseq([(32).midicps,
					(26).midicps,
					(34).midicps,
				],inf),
				\atk, ~attack,
				\rel, ~release,
				\sus, Pseq(~sustains,inf),
				\dur, Pseq(~durations,inf),
				\out, [0, 1],
				\group, ~mainGrp
			).play(~tempoClock);
			);

		}); // s.makeBundle
	},~tempoClock);
	); // \playpart1

	e.add(\playpart2 ->Task({

		3.do{
			|i|
			e[\stoppart].value(i + 1);
		};

		s.makeBundle(s.latency, {

			~p2_events.add(\p2e1 -> Pbind(\instrument, \whistle,
				\freq, Pseq([85, 88, 81, 88, 83, 88, 80, 83].midicps, inf),
				\atk, 0.39,
				\legato, 1,
				\dur, Pseq([1,2],inf),
				\amp, 8,
				\out, [0,1],
				\group, ~mainGrp
			).play(~tempoClock,quant:1);
			);

			~p2_events.add(\p2e2 -> Pbind(\instrument, \playblipbuf,
				\bufnum, ~buffers[\Blip][0].bufnum,
				\amp, 10,
				\rate, Pseq([1,2],inf),
				\rel, Pseq([0.4,1.2],inf),
				\dur, Pseq([1,2],inf),
				\out, [0,1],
				\group, ~mainGrp,
			).play(~tempoClock,quant:1);
			);

			~p2_events.add(\p2e3 -> Pbind(\instrument, \wow,
				\freq, Pseq([ [49,52],
					[45,49],
					[47,51],
					[44,47],
					[45,56],
					[42,52],
					[44,54],
					[40,47,52],
				].midicps,inf),
				\dur, Pseq([3,3,3,3],inf),
				\out, [0,1],
				\group, ~mainGrp
			).play(~tempoClock,quant:1);
			);

			~p2_events.add(\p2e4 -> Pbind(\instrument, \bass808,
				\amp, 0.4,
				\freq, Pseq([ 37,
					33,
					35,
					32,
					33,
					30,
					32,
					28 ],inf),
				\dur, Pseq([3,3,3,3],inf),
				\out, [0,1],
				\group, ~mainGrp
			).play(~tempoClock,quant:1);
			);

			~p2_events.add(\p2e5 -> Pbind(
				\instrument, \saw,
				\freq, Pseq([ [49,52],
					[45,49],
					[47,51],
					[44,47],
					[45,56],
					[42,52],
					[44,54],
					[40,47,52],
				].midicps,inf),
				\dur, Pseq([3,3,3,3],inf),
				\cutoff, 1000,
				\atk, 0.7,
				\rq, 0.6,
				\amp, 0.3,
				\rel, 2,
				\out, [0,1],
				\group, ~mainGrp
			).play(~tempoClock,quant:1);
			);
		});// s.makeBundle
	},~tempoClock)
	); // \playpart2

	e.add(\playpart3 -> Task({

		3.do{
			|i|
			e[\stoppart].value(i + 1);
		};

		// Modulation
		~freqCtrlSrcSynth = SynthDef(\freqCtrlSrc, {
			Out.kr(~bus[\freqCtrlBus], SinOsc.kr(0.5, pi/2).range(100,10000));
		}).play(target: ~ctrlSrcGrp);

		~panCtrlSrcSynth = SynthDef(\panCtrlSrc, {
			Out.kr(~bus[\panCtrlBus], SinOsc.kr(0.5, pi/2));
		}).play(target: ~ctrlSrcGrp);

		s.sync;

		~percBpfSynth = Synth(\percbpfbuf, [
			\in, ~bus[\bpf],
			\bpfmix, 1,
		], target: ~effectsGrp);

		~percBpfSynth.map(\freq, ~bus[\freqCtrlBus]);
		~percBpfSynth.map(\pan, ~bus[\panCtrlBus]);

		s.sync;

		s.makeBundle(s.latency,{
			~p3_events.add(\p3e1 -> Pbind(
				\instrument, \warmbeautiful,
				\freq, Pseq([([0,4,7,11] + 40).midicps,
					([0,4,7,11] + 43).midicps], inf),
				\dur, Pseq([4,4], inf),
				\atk, 0.2,
				\rel, 4,
				\amp, 2,
				\out, 0,
				\group, ~mainGrp,
			).play(~tempoClock);
			);

			~p3_events.add(\p3e2 -> Pbind(\instrument, \sawbass,
				\freq, Pseq([40,40,40,35,31,31,38,38].midicps,inf),
				\cutoff, 100,
				\rq, 0.9,
				\amp, 0.7,
				\dur, Pseq([0.75,1.25],inf),
				\out, 0,
				\group, ~mainGrp,
			).play(~tempoClock);
			);

			~p3_events.add(\p3e3 -> Pbind(
				\instrument, \can,
				\ff, Pxrand(Array.fill(8, {|i| i*2 + 500}),inf),
				\dur, Pseq([0.25,0.25,0.50,0.25],inf),
				\rel, 0.12,
				\amp, Pseq([0.05, 0.125, 0.075, 0.025], inf),
				\out, ~bus[\bpf],
				\group, ~mainGrp,
			).play(~tempoClock);
			);

			~p3_events.add(\p3e4 -> Pbind(
				\instrument, \basskick,
				\dur, Pseq([2], inf),
				\amp, 2,
				\freq, 60,
				\out, 0,
				\group, ~mainGrp,
			).play(~tempoClock);
			);

			~p3_events.add(\p3e5 -> Pbind(
				\instrument, \snare,
				\bufnum, ~buffers[\Percussion][0].bufnum,`
				\dur, Pseq([Rest(1), 1], inf),
				\amp, 0.02,
				\freq, 60,
				\out, ~bus[\bpf],
				\group, ~mainGrp,
			).play(~tempoClock);
			);

		}); // s.makeBundle
	},~tempoClock);
	); // playpart3

	e.add(\stoppart -> {
		arg partnum;
		if(partnum == 1){

			~p1_events.keysValuesDo{
				|key, value|
				value.stop;
			};
		};

		if(partnum == 2){
			~p2_events.keysValuesDo{
				|key, value|
				value.stop;
			};
		};

		if(partnum == 3){
			~p3_events.keysValuesDo{
				|key, value|
				value.stop;
			};
		};

		if( (partnum != 1) && (partnum != 2) && (partnum != 3)){
			("Part " ++ partnum ++ " does not exist!").postln;
		};

	});

	e.add(\playall -> Task({
		e[\playpart1].play;
		3.wait;
		e[\stoppart].value(1);
		8.wait;
		e[\playpart2].play;
		24.wait;
		e[\stoppart].value(2);
		4.wait;
		e[\playpart3].play;
		16.wait;
		e[\stoppart].value(3);
	}, ~tempoClock)
	);

	// Effects
	e.add(\delay -> {
		arg out = 0;
		~delaySynth = Synth(\delay, [\in, ~bus[\delay], \mix, 1, \lines, 8, \amp, 1, \out, out],
			target:~effectsGrp,
		);
	}
	);

	e.add(\reverb -> {
		arg out = 0;
		~reverbSynth = Synth(\reverb, [\in, ~bus[\reverb], \mix, 1, \lines, 20, \dt_max, 0.5, \amp, 10, \out, out],
			target:~effectsGrp,
		);
	}
	);

	e.add(\pitchshift -> {
		arg in, out = 0;
		~pitchshiftSynth = Synth(\pitchshift, [\in, in, \out, out, \pr, 2, \pd, 0.01, \td,0.01, \mix, 0.7],
			target:~effectsGrp,
		);
	}
	);

	// Playback
	e.add(\record-> {
		arg buffer, in=0;
		~audioSaved.clear;
		Synth(\record,
			[\in, in, \bufnum, ~audioSaved.bufnum],
			target:~playbackGrp,
			addAction:'addToTail'
		);
	}
	);

	e.add(\playback -> {
		arg buffer, out=0;
		~playbackSynth = Synth(\dopeplayback,
			[\bufnum, ~audioSaved.bufnum, \time, ~recordTime, \vmix, 0.3, \lpf, 1000, \playrate, 0.75, \out, out],
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
	SynthDef(\reverb, {
		arg in, out=0,
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

	SynthDef(\delay, {
		arg in, out = 0, amp = 1, mix=1, delayTimeInterval = 0.45;
		var dry, wet, final, maxDelayTime,lines,env;
		lines = 8;
		dry = In.ar(in, 2);

		maxDelayTime = delayTimeInterval * lines;
		wet = 0;
		lines.do{
			|i|
			wet = wet + DelayN.ar(dry, maxDelayTime, delaytime: i * delayTimeInterval, mul: (maxDelayTime - (delayTimeInterval*i))/maxDelayTime);
		};

		final = XFade2.ar(dry, wet, mix * 2 - 1);
		Out.ar(out, final * amp);
	}).add;

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

	SynthDef(\sawbass,{
		arg freq=440, atk=0.001, rel=2, amp=1, phase=0, cutoff=1000, rq=0, out =0 ,decay=1;
		var sig, env;

		env = EnvGen.kr(Env.new([0,1,0],[atk,rel],[3,-5]),doneAction:2);
		sig = Saw.ar([freq-1,freq+1],amp);

		sig = RLPF.ar(sig, cutoff, rq, amp);

		Out.ar(out, sig * env );
	}
	).add;

	SynthDef(\bass808,{
		arg freq, atk=0.01, sus=1, rel=1.5, out=[0,1], amp;
		var sig,env;

		env = EnvGen.kr(Env([0,1,1,0],[atk, sus,rel]),doneAction:2);
		sig = clip2(SinOsc.ar(freq, 3*pi/2,amp),1);
		Out.ar(out,sig*env);

	}
	).add;

	SynthDef(\record, {
		arg in, bufnum;
		var inArray, env;
		env = EnvGen.kr(Env([0,1,1,0],[0.1,~recordTime,2],[4,-4]),doneAction:2); // needed to free node after its done
		inArray = In.ar(in*env, 2);
		RecordBuf.ar(inArray, bufnum, loop:0, doneAction:2);
	}).add;

	SynthDef(\dopeplayback, {
		arg bufnum, amp = 1, mooglpf = 1000, hpf = 10000,  playrate = 1, rateChange=0,
		vroom = 0.2, vmix=1, vdamp=0.01, out = [0,1];
		var bufsize, length, env, startup, sig;

		startup = playrate / 0.5;
		bufsize = BufFrames.kr(bufnum);
		length = bufsize / BufSampleRate.kr(bufnum); // correct for mono and stereo?

		sig = PlayBuf.ar(2, bufnum, Sweep.ar(Impulse.kr(0), Line.kr(1,0,startup)) + rateChange, doneAction:2);
		sig = BMoog.ar(sig, mooglpf, mul:0.7); // distorts
		sig = FreeVerb.ar(sig, vmix, vroom, vdamp);
		sig = Pan2.ar(sig, SinOsc.ar(2).range(-1,1));

		Out.ar(out, sig  * amp);
	}).add;

	SynthDef(\whistle, {
		arg freq, dur = 1, atk = 0.03, amp = 2, out = [0,1];
		var env, sig;

		env = EnvGen.ar(Env.adsr(atk, 0.2, 0.5, 0.6, peakLevel:0.5,curve:-4));
		sig = BPF.ar( PinkNoise.ar(mul: Line.kr(1,0,dur,doneAction:2)), {freq + (2**(LFNoise2.ar(freq) * Line.kr(-2, 0, 2) ))} ! 3, 0.001, 5);
		sig = Splay.ar(sig,0);

		Out.ar(out, sig * env * amp);
	}).add;

	SynthDef(\wow, {arg freq = 60, amp = 0.1, gate = 1, wowrelease = 3, out=[0,1];
		var chorus, source, filtermod, env, snd;

		chorus = Lag.kr(freq, 2) * LFNoise2.kr([0.4, 0.5, 0.7, 1, 2, 5, 10]).range(1, 1.02); // memorize this
		source = LFSaw.ar(chorus) * 0.5; // source
		filtermod = SinOsc.kr(1/16).range(1, 10); // filter
		env = Env.asr(1, amp, wowrelease).kr(2, gate); // asr
		snd = LPF.ar(in: source, freq: freq * filtermod, mul: env);
		Out.ar(out, Splay.ar(snd)) // mix 7 channels down to stereo w splay
	}).add;

	SynthDef(\playblipbuf, {
		arg bufnum, rate=1, rel=0.5,amp=1, out=[0,1];
		var env, sig, siglo;
		env = EnvGen.ar(Env(times:[0.01,rel], curve:[1,2]),doneAction:2);
		sig = PlayBuf.ar(2, bufnum,rate);
		siglo = RLPF.ar(sig,80,0.2,3);
		sig = FreeVerb2.ar(sig[0],sig[1],0.32, 0.2, 0.1, 0.3);
		sig = sig + siglo;
		sig = LPF.ar(sig, 1250);
		Out.ar(out, sig * env * amp);
	}).add;

	SynthDef(\saw,{
		arg freq=440, atk=0.001, rel=2, amp=1, phase=0, cutoff=1000, rq=0, out = [0,1];
		var sig, env, chorus, filtermod;

		chorus = Lag.kr([freq-1,freq+1], 2) * LFNoise2.kr([0.4, 0.5, 0.7, 1, 2, 5, 10]).range(1, 1.02); // memorize this

		filtermod = SinOsc.kr(1/16).range(1, 10); // filter
		env = EnvGen.kr(Env.new([0,1,0],[atk,rel],[3,-5]),doneAction:2);
		sig = Saw.ar(chorus,amp);

		sig = RLPF.ar(sig, cutoff, rq, amp);

		Out.ar(out, sig * env );
	}
	).add;

	SynthDef(\can, {
		arg ff=500, rel=0.1, vmix=0.1, vdamp=0.01,
		amp = 2, out = 0;
		var env, sig;

		env = EnvGen.ar(Env.perc(releaseTime:rel),doneAction:2);
		sig = WhiteNoise.ar;
		sig = BPF.ar(sig,ff);
		sig = sig * env;
		sig = GVerb.ar(sig, damping:vdamp, revtime:0.3, earlyreflevel:1);

		Out.ar(out, sig[0] * amp);
	}).add;

	SynthDef(\warmbeautiful, {

		arg amp = 1, out = 0, delayTimeInterval = 0.2, freq = 440,
		atk = 0.1, rel = 3;
		var src, noise, aux, final, srcEnv, noiseEnv, masterEnv, rqmod, maxDelayTime;
		var lines = 20;

		noiseEnv = EnvGen.ar(Env.perc);
		srcEnv = EnvGen.ar(Env.perc);
		masterEnv = EnvGen.ar(Env([0, 1, 0.05, 0], times:[atk,rel]), doneAction:2);
		rqmod = Sweep.ar(Impulse.kr(0), 2).exprange(2,0.4);

		src = Saw.ar([freq - 0.5, freq + 0.5], 0.2) * srcEnv;
		src = RLPF.ar(src, freq*4, rqmod);
		noise = WhiteNoise.ar(0.5) * noiseEnv;
		noise = BHiPass4.ar(noise, freq*2, rqmod, 0.05);
		aux = noise + src;

		maxDelayTime = delayTimeInterval * lines + delayTimeInterval;
		final = 0;
		lines.do{
			|i|
			final = final + DelayN.ar(aux, maxDelayTime, i * delayTimeInterval);
		};

		final = BPF.ar(final, freq*4, rqmod);
		Out.ar(out, (final * amp * masterEnv) ! 2);
	}
	).add;


	SynthDef(\snare, {
		arg bufnum, freq = 60, amp = 1, out = 0, pan = 0, bpfcf = 2100;
		var file, noise1, noise2, sig, final;

		file = PlayBuf.ar(2,bufnum, rate:0.92,startPos:BufFrames.kr(bufnum)*(1 - 0.2)) * EnvGen.ar(Env.perc(releaseTime:0.2)) * 20;
		noise1= BPF.ar(WhiteNoise.ar,2200) * EnvGen.ar(Env(levels:[0,1,1,0],times:[0.02,0.01,2], curve:[\lin, \lin, \exp]), doneAction:2 );
		noise2 = RLPF.ar(WhiteNoise.ar(2),1000) * EnvGen.ar(Env.perc(releaseTime:1));

		sig = noise1 + noise2 + file;
		sig = BPF.ar(sig, bpfcf, 0.8);
		sig = GVerb.ar(sig, 0.98674687743186945, 10, XLine.kr(0.42,0.1,2));//Sweep.kr(Impulse.kr(0), 3));//0.5);

		final = 0;
		10.do{
			|i|
			final = final + BPF.ar(DelayN.ar(sig, 3, 0 + (0.1*i), 1 - (i * 0.1)), (bpfcf + (i*900)), 0.8);
		};
		final = Pan2.ar(final, pan);
		Out.ar(out, final * amp);
	}).add;

	SynthDef(\basskick, {
		arg freq = 60,rel=0.1, vmix=0.1, vdamp=0.01,
		amp = 2, out = 0;
		var env, sig;

		env = EnvGen.ar(Env.perc(releaseTime:rel),doneAction:2);

		sig = {WhiteNoise.ar} + SinOsc.ar(freq,mul:0.5) + SinOsc.ar(freq + 15,mul:0.45);
		sig = BPF.ar(sig,freq,0.7);
		//sig = Limiter.ar(sig,2,0.001);
		sig = (sig * env) ! 2;

		Out.ar(out, sig * amp);
	}).add;

	SynthDef(\percbpfbuf, {
		arg in, atk=0, sus=0, rel=3, c1=1, c2=(-1),
		rate=1, spos=0, freq=440, rq=1, bpfmix=0,
		pan=0, amp=1, out=0;
		var sig, env;
		/*env = EnvGen.kr(Env([0,1,1,0],[atk,sus,rel],[c1,0,c2]),doneAction:2);*/
		sig = In.ar(in, 1);
		sig = XFade2.ar(sig, BPF.ar(sig, freq, rq, 1/rq.sqrt), bpfmix*2-1);
		/*sig = sig * env;*/
		sig = Pan2.ar(sig, pan, amp);
		Out.ar(out, sig);
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
e[\playall].play;
e[\playall].stop;
e[\record].value;
e[\playback].value;
e[\down].value;
e[\up].value;
// -------------------
e[\playpart1].play;
e[\playpart1].reset;
e[\stoppart].value(1);
e[\playpart2].play;
e[\playpart2].reset;
e[\stoppart].value(2);
e[\playpart3].play;
e[\playpart3].reset;
e[\stoppart].value(3);
s.plotTree;
ServerTree.removeAll;





