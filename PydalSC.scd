//tempoclock with beat set to 1 cycle length
(var midiOut, pythonOSCport, channelPatternMap, chanBackupPatMap, channelInd, drumTypes, startPattern, playStepGenerator, recieveBackupPattern, stopPattern, patternRead, timeListToDurationList, sendSample, midiChannel, masterTempoClock, tempoClockMap, loopStartFunctions, masterClockBeat, masterClockTempoHandler, channelTypeMap, python_FH_OSCport, channelMetaInfo, changeChannelTempo, syncClocks, instrumentMidiOut, maxPort, lemurBouncePort, chanPhaseTrackerTasks, ballVisualPort, abletonPort, runRamp;

midiOut = MIDIOut.newByName("IAC Driver", "Bus 3");
instrumentMidiOut = MIDIOut.newByName("IAC Driver", "Bus 2");
midiOut.latency = 0;
instrumentMidiOut.latency = 0;

//endpoints for various applications that I control using Pydal
pythonOSCport = NetAddr("localhost", 34345);
python_FH_OSCport = NetAddr("localhost", 13371);
maxPort = NetAddr("localhost", 5435);
ballVisualPort = NetAddr("localhost", 7400);
lemurBouncePort = NetAddr("localhost", 7100);
abletonPort = NetAddr("localhost", 7110);

channelPatternMap = Dictionary();        //maps channelKey -> currently playing buffer on that pattern
chanBackupPatMap = Dictionary();         //maps channelKey -> buffer to be queued up next
channelInd = Dictionary();               //maps channelKey -> index in the hit buffer that has most recently been played
tempoClockMap = Dictionary();            //maps channelKey -> the clock that the channel runs on
loopStartFunctions = Dictionary();       //a place holder variable used in the implementation of syncing the start of a loop to a quantized beat
channelTypeMap = Dictionary();           //maps channelKey -> the type-string of the channel
channelMetaInfo = Dictionary();          //maps channelKey -> the extra info necessary for playing that channel instance
chanPhaseTrackerTasks = Dictionary();    //The speed of the clocks running each channel can be sped-up/slowed individually. This tracks their relative phase compared to the master clock.

//TODO - parametrize this
midiChannel = 0;


//mapping of drum strings to midi notes corresponding to my personal Ableton setup
drumTypes = Dictionary();
drumTypes["~"] = 1;
drumTypes["bd"] = 30;
drumTypes["lt"] = 40;
drumTypes["ht"] = 50;
drumTypes["sn"] = 60;
drumTypes["ho"] = 70;
drumTypes["hc"] = 75;
drumTypes["cr"] = 80;
drumTypes["rd"] = 85;
drumTypes["bot"] = 90;
drumTypes["cp"] = 100;
drumTypes["bin"] = 102;
drumTypes["bend"] = 104;
drumTypes["aud"] = 108;

//OSC endpoint that starts the playing of a pattern
//msg[1] is the key identifying the channel being played on
//msg[2] is the string representation of the pattern getting played
//msg[3] is the total length in beats of the pattern
//msg[4] is the "type" of the pattern
//msg[5...] is meta-pattern info for this channel (contextual per pattern type)
startPattern = {|msg, time, addr, recvPort|
    //parse string to pattern
    var patternList, loopFrac, ind, startDelay, chanClock;
    patternList = patternRead.(msg[2].asString);
    ["PLAY START", patternList, masterTempoClock.beats].postln;

    maxPort.sendRaw((["/pattern", msg[1].asInt] ++ patternList.collect({|elem| elem[0]})).asArray.asRawOSC);

    //save pattern to map
    channelPatternMap[msg[1]] = timeListToDurationList.(patternList, msg[3].asFloat);
    chanBackupPatMap[msg[1]] = [];

    channelTypeMap[msg[1]] = msg[4].asSymbol;
    channelMetaInfo[msg[1]] = msg[5..];

    //create channel tempo clock if needed
    if(tempoClockMap.keys.includes(msg[1]).not,
        {
            chanClock = TempoClock.new(masterTempoClock.tempo, masterTempoClock.beats);
            tempoClockMap[msg[1]] = chanClock;
            chanClock.beats = masterTempoClock.beats;
        },
        {chanClock = tempoClockMap[msg[1]]}
    );

    if(chanPhaseTrackerTasks[msg[1]].isNil, {
        chanPhaseTrackerTasks[msg[1]] = Task({
            {
                maxPort.sendMsg("/phaseVal", msg[1].asInt, (masterTempoClock.beats-tempoClockMap[msg[1]].beats)%1);
                0.03.wait;
            }.loop
        });
        chanPhaseTrackerTasks[msg[1]].play;
    });

    chanClock.clear;

    tempoClockMap.values.do({|v| v.beats.postln;});

    /*channelInd[msg[1]] = 0;
    chanClock.sched(chanClock.timeToNextBeat, playStepGenerator.(msg[1]));*/
    tempoClockMap[msg[1]].clear();
    channelInd[msg[1]] = 0;

    loopStartFunctions[msg[1]] = {chanClock.sched(0, playStepGenerator.(msg[1]))};
};
OSCFunc(startPattern, "/pydalPlay");


//A function that schedules an individual hit to occur and handles the state change throughout the progression of a buffer
//TODO - use tasks here instead? (tasks are cleaner but this could be more flexible)
playStepGenerator = {|i|
	var playStep = {
		//if list len == 0, exit
		var retVal = nil;

        //if last step (or < 20 ms from end?), set backupPat to actual pattern
        if((channelInd[i] == 0) && (chanBackupPatMap[i].size > 0), {
            //"LOADED BACKUP".postln;
            channelPatternMap[i] = chanBackupPatMap[i]
        });

		if(channelPatternMap[i].size != 0, {
			var ind = channelInd[i];
			var patList = channelPatternMap[i];
			var step = patList[ind];
			var dur = step[0];

			step[1].do({|samp| sendSample.(samp, i, ind)});
            ["STEP", i, ind, tempoClockMap[i].beats, step].postln;

			if(ind == (patList.size-1), {
                pythonOSCport.sendMsg("/pydalGetUpdate-"++i);
                ["REQUESTING PATTERN", i, ind, patList].postln;
            });

			//update indexes appropriately
			channelInd[i] = (ind+1)%patList.size;

			//return (d) - i.e. schedule next step on channel
			retVal = dur;
			//["RETVAL1", retVal].postln;
		});
        // ["RETVAL2", retVal].postln;
		retVal
	};
	playStep
};

// endpoint for changing the tempo of a single channel
//msg[1] is the tempo (in bmp)
//msg[2] is the channelKey to change the clock for
changeChannelTempo = {|msg, time, addr, recvPort|
    //create channel tempo clock if needed
    //[msg, tempoClockMap.keys].postln;
    if(tempoClockMap.keys.includes(msg[2]),{
        tempoClockMap[msg[2]].tempo = msg[1].asFloat/60;

        //maxPort.sendMsg("/phaseVal", msg[2].asInt, (masterTempoClock.beats-tempoClockMap[msg[2]].beats)%1);
    });
};
OSCFunc(changeChannelTempo, "/changeChannelTempo");


// allows for the resyncing of the tempo and/or phase of an arbitrary subset of channels
//msg[1] is type of sync "phase, tempo, both"
//msg[2] is key of clock to sync to
//msg[3...] is keys of other clocks to sync
syncClocks = {|msg, time, addr, recvPort|
    //create channel tempo clock if needed
    if(tempoClockMap.keys.includes(msg[2]) || (msg[2].asSymbol == 'master'),{
        var refClock = if(msg[2].asSymbol == 'master', masterTempoClock, tempoClockMap[msg[2]]);
        msg[3..].do({|key|
           if(tempoClockMap.keys.includes(key), {
                var clockToSync = tempoClockMap[key];
                if(['tempo', 'both'].includes(msg[1].asSymbol), {clockToSync.tempo = refClock.tempo});
                if(['phase', 'both'].includes(msg[1].asSymbol), {
                    clockToSync.clear;
                    clockToSync.beats = refClock.beats;
                    channelInd[key] = 0;
                    if(chanBackupPatMap[key].isNil.not, {clockToSync.sched(refClock.timeToNextBeat, playStepGenerator.(key))});
                });
            });
        });
        if(['phase', 'both'].includes(msg[1].asSymbol), {
            var refKey = msg[2];
            refClock.clear;
            channelInd[refKey] = 0;
            if(chanBackupPatMap[refKey].isNil.not, {refClock.sched(refClock.timeToNextBeat, playStepGenerator.(refKey))});
        });
    });
};
OSCFunc(syncClocks, "/syncClocks");



//msg[1] is the channel being played on
//msg[2] is the backup pattern
//msg[3] is the total length in beats of the pattern
recieveBackupPattern = {|msg, time, addr, recvPort|
	//parse string and save it to backupmap

    var patternList = patternRead.(msg[2].asString);
    ["GOT BACKUP", patternList].postln;
    maxPort.sendRaw((["/pattern", msg[1].asInt] ++ patternList.collect({|elem| elem[0]})).asArray.asRawOSC);

    chanBackupPatMap[msg[1]] = timeListToDurationList.(patternList,  msg[3].asFloat);
};
OSCFunc(recieveBackupPattern, "/pydalSendUpdate");



//msg[1] is ind of channel to stop
stopPattern = {|msg, time, addr, recvPort|
	if(channelPatternMap.keys.includes(msg[1]), {channelPatternMap[msg[1]] = []});
	["STOP PATTERN", channelPatternMap.keys.includes(msg[1]), msg[1]].postln;
    masterTempoClock.sched(masterTempoClock.timeToNextBeat - 0.01, {tempoClockMap[msg[1]].clear()});
    chanBackupPatMap[msg[1]] = nil;
    if(channelTypeMap[msg[1]] == 'loop', {
        instrumentMidiOut.allNotesOff(channelMetaInfo[msg[1]][0]);
    });
};
OSCFunc(stopPattern, "/pydalStop");


//start the clock for this module so that it is in sync/phase with the master clock
f = {|msg, time, addr, recvPort|
	//msg[1] is the new BEAT DURATION (not tempo)
	masterTempoClock = TempoClock.new(1/msg[1], 0);
	t = masterTempoClock;
};
OSCFunc(f, "/masterClockBeat").oneShot;


//allows Pydal to be clock-synced to other running SuperCollider applications
//msg[1] is the new BEAT DURATION (not tempo)
masterClockTempoHandler = {|msg, time, addr, recvPort|
	//(0..3).do({|i| metronomeClocks[i].tempo = 1/msg[1].asFloat})
	masterTempoClock.tempo =  1/msg[1].asFloat;
	tempoClockMap.values.do({|clock| clock.tempo = 1/msg[1].asFloat});
};
OSCFunc(masterClockTempoHandler, "/masterClockTempo");

//msg[1] is the new BEAT DURATION (not tempo)
masterClockBeat = {|msg, time, addr, recvPort|
	loopStartFunctions.keys.do({|key|
		if(loopStartFunctions[key] != nil, {
			["START", masterTempoClock.beats].postln;
			loopStartFunctions[key].();
			loopStartFunctions[key] = nil;
		})
	});
	//["PYDAL BEAT", masterTempoClock.beats].postln;
};
OSCFunc(masterClockBeat, "/masterClockBeat");

//parses the string representation of the buffer into a SuperCollider array
patternRead = {|patternStr|
	var patternList = List.new;
	patternStr.split($;).do({|s|
		var step = s.split($-);
		var time = step[0].asFloat;
		var sampSet = Set.newFrom(step[1].split($,));
		patternList.add([time, sampSet]);
	});
	patternList
};

//further formatting of the incoming buffer to an easier representation for scheduling
timeListToDurationList = {|oldList, totalLength|
    var pList = List.new;
    if(oldList.size > 1,
        {
            (0..oldList.size-2).do({|i|
                pList.add([oldList[i+1][0] - oldList[i][0], oldList[i][1]]);
            });

    });
    pList.add([totalLength - oldList[oldList.size-1][0], oldList[oldList.size-1][1]]);

    pList
};

runRamp = {|oscAddr, startVal, endVal, dur|
    var hz = 0.01;
    var numSteps = (dur/hz).floor;
    var steps = List.fill(numSteps, {|i| i/numSteps});
    var pat = Pbind(
        \delta, hz,
        \lerp, Pseq(steps),
        \play, {
            abletonPort.sendMsg(oscAddr, (~lerp*endVal)+((1-~lerp)*startVal))
        }
    );
    pat.play(masterTempoClock);
};

// handles what happens during a "hit" for all of the different channel types
//TODO - handle ~ (rest) for existing types
sendSample = {|drumStr, chan, ind|
    if(channelTypeMap[chan] == 'pydal', {
        var drumInd, drumType, patMidiChannel;
        drumInd = drumStr.split($:)[1];
        drumInd = if(drumInd.isNil, 0, {drumInd.asInteger});
        drumType = drumTypes[drumStr.split($:)[0]].asInteger;
        patMidiChannel = if(channelMetaInfo[chan][0].isNil, midiChannel, channelMetaInfo[chan][0]);

        maxPort.sendMsg("/hitInfo", chan.asInt, ind.asInt, (masterTempoClock.beats-tempoClockMap[chan].beats)%1);

        //todo - send cc map stuff if applicable
        Task({
            midiOut.noteOn(patMidiChannel, drumType+drumInd); //maybe add velocity based on gain?
            0.0001.wait;
            midiOut.noteOff(patMidiChannel, drumType+drumInd);
        }).play;
    });

    //aa is top-left, but remapped to coordinates where 0,0 is bottom-left, to match chordScenePad
    /*channelMetaInfo has 1 element - the midiChannel number of the spatializer.py object that
     the playChord info will be sent to*/
    if(channelTypeMap[chan] == 'chord', {
        var rowChar = "hgfedcba";
        var colChar = "abcdefgh";
        var ind = rowChar.find(drumStr[0])*10 + colChar.find(drumStr[1]);
        python_FH_OSCport.sendMsg("/playChord-" ++ channelMetaInfo[chan][0].asString, ind);
    });
    if(channelTypeMap[chan] == 'loop', {
        var drumSplit = drumStr.split($^);
        var hitInfo;
        ["DRUM SPLIT", drumSplit].postln;
        hitInfo = [drumSplit[0].asInt, drumSplit[1].asInt, drumSplit[2].asInt, drumSplit[3]];
        if(hitInfo[3].asSymbol == 'on', {instrumentMidiOut.noteOn(hitInfo[2], hitInfo[0], hitInfo[1])});
        if(hitInfo[3].asSymbol == 'off', {instrumentMidiOut.noteOff(hitInfo[2], hitInfo[0], hitInfo[1])});
    });
    if(channelTypeMap[chan] == 'ballState', {
        ballVisualPort.sendMsg("/loadWorld", drumStr);
    });
    if(channelTypeMap[chan] == 'funcTrigger', {
        lemurBouncePort.sendMsg("/funcTrigger", drumStr);
    });

    if(channelTypeMap[chan] == 'roboDrum', {
        var hitInd = ['a', 'b', 'c', 'd', 'e'].indexOf(drumStr.asSymbol);
        if(hitInd.isNil.not,  {maxPort.sendMsg("/roboDrum", hitInd)});
    });

    if(channelTypeMap[chan] == 'midi', {
        if(drumStr.asSymbol != '~', {
            var patMidiChannel = channelMetaInfo[chan][0];
            var ccChannel = channelMetaInfo[chan][1];
            var noteLen = channelMetaInfo[chan][2];
            var digits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
            var letters = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'];
            var noteOnFunc = {|fullNote|
                var lastChar = drumStr.wrapAt(-1).asSymbol;
                var vel = if(digits.includes(lastChar), {64}, {digits.indexOf(lastChar)/26*127});
                var note = if(fullNote, drumStr.asInt, drumStr[1..].asInt); //this method will parse a valid prefix as an int and throw away the rest
                midiOut.noteOn(patMidiChannel, note, vel);
            };
            if(drumStr[0].asSymbol == 'c', {
                midiOut.control(0, ccChannel, drumStr[1..].asInt); //ignore channel for CC and just send on 0
            });
            if(drumStr[0].asSymbol == 'n', {
                noteOnFunc.(false);
            });
            if(drumStr[0].asSymbol == 'f', {
                midiOut.noteOff(patMidiChannel, drumStr[1..].asInt, 64);
            });
            if(digits.includes(drumStr[0].asSymbol), {
                Task({
                    noteOnFunc.(true);
                    (noteLen/tempoClockMap[chan].tempo).wait;
                    midiOut.noteOff(patMidiChannel, drumStr.asInt, 64);
                }).play;
            });
        });
    });
    if(channelTypeMap[chan] == 'osc', {
        if(drumStr.asSymbol != '~', {
            abletonPort.sendMsg(chan, drumStr.asFloat);
        });
    });
    if(channelTypeMap[chan] == 'ramp', {
        if(drumStr.asSymbol != '~', {
            var val = drumStr.asString.split($/)[0].asFloat;
            var dur = drumStr.asString.split($/)[1].asFloat;
            var metaInfo = channelMetaInfo[chan];
            runRamp.(chan, metaInfo[1], val, dur);
            metaInfo[1] = val;

        });
    });
};
~testEnvVar.postln;
)