% Distillation column fault diagnosis expert system - strictly Prolog core.
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(aggregate)).
:- use_module(library(pairs)).
:- thread_local observation/2.

% ---- Reference operating point: ref(Var, Value, Unit, Label). Modelling assumption: binary benzene-toluene tray column, atmospheric.
ref(f,100.0,'kmol/h','Feed flow rate').
ref(d,50.0,'kmol/h','Distillate flow rate').
ref(b,50.0,'kmol/h','Bottoms flow rate').
ref(l,100.0,'kmol/h','Reflux flow rate').
ref(qr,1500.0,'kW','Reboiler duty').
ref(qc,1450.0,'kW','Condenser duty').
ref(xd,0.98,'mole fraction','Distillate purity').
ref(xb,0.02,'mole fraction','Bottoms light-key content').
ref(ttop,82.0,'deg C','Top tray temperature').
ref(tbot,112.0,'deg C','Reboiler temperature').
ref(p,101.3,'kPa','Top pressure').
ref(dp,6.0,'kPa','Column differential pressure').
ref(tf,95.0,'deg C','Feed temperature').
ref(ldrum,50.0,'%','Reflux drum level').
ref(lbot,50.0,'%','Bottoms sump level').

loadObs(Obs) :- retractall(observation(_,_)), forall(member(V-X,Obs), assertz(observation(V,X))).
r4(X,Y) :- Y is round(X*10000)/10000.
loadFactor(L) :- observation(f,F), ref(f,FR,_,_), !, L is F/FR.
loadFactor(1.0).
% Default: references hold at nominal load. Exception: hydraulic and duty references scale with load.
effRef(dp,R) :- !, ref(dp,R0,_,_), loadFactor(L), R is R0*L*L.
effRef(V,R) :- memberchk(V,[qr,qc]), !, ref(V,R0,_,_), loadFactor(L), R is R0*L.
effRef(V,R) :- ref(V,R,_,_).
dev(V,E) :- observation(V,X), effRef(V,R), E is (X-R)/R.
rrDev(E) :- observation(l,L), observation(d,D), D > 0, ref(l,L0,_,_), ref(d,D0,_,_), E is ((L/D)-(L0/D0))/(L0/D0).
mb(E) :- observation(f,F), observation(d,D), observation(b,B), F > 0, E is (F-D-B)/F.

% ---- Instrumentation defaults and exceptions
reliable(V) :- \+ unreliable(V).
unreliable(ttop) :- conflict(c1,_).
unreliable(d) :- conflict(c2,_).
unreliable(b) :- conflict(c2,_).
conflict(c1,'Top temperature disagrees with on-specification distillate at normal pressure') :-
    dev(xd,E1), E1 >= -0.01, dev(ttop,E2), abs(E2) > 0.04, \+ (dev(p,E3), abs(E3) > 0.03).
conflict(c2,'Flow measurements violate the mass balance while both inventories are stable') :-
    mb(E), abs(E) > 0.05, observation(ldrum,_), observation(lbot,_),
    \+ (dev(ldrum,E1), abs(E1) > 0.15), \+ (dev(lbot,E2), abs(E2) > 0.15).

% ---- Symptom rules (Horn clauses over derived deviations)
sym(highDp) :- dev(dp,E), E > 0.30.
sym(lowDp) :- dev(dp,E), E < -0.35.
sym(lowTopPurity) :- dev(xd,E), E < -0.02.
sym(highBottomsImpurity) :- dev(xb,E), E > 0.50.
sym(highTopTemp) :- reliable(ttop), dev(ttop,E), E > 0.04.
sym(lowBottomTemp) :- dev(tbot,E), E < -0.04.
sym(highPressure) :- dev(p,E), E > 0.08.
sym(lowPressure) :- dev(p,E), E < -0.08.
sym(lowReflux) :- rrDev(E), E < -0.20.
sym(lowBoilup) :- dev(qr,E), E < -0.12.
sym(lowCondDuty) :- dev(qc,E), E < -0.12.
sym(massImbalance) :- reliable(d), reliable(b), mb(E), abs(E) > 0.05.
sym(highBottomsLevel) :- dev(lbot,E), E > 0.30.
sym(lowDrumLevel) :- dev(ldrum,E), E < -0.30.
sym(coldFeed) :- dev(tf,E), E < -0.08.
sym(highBoilup) :- dev(qr,E), E > 0.15.
sym(instrumentConflict) :- once(conflict(_,_)).

symInfo(highDp,s1,'Differential pressure above load-corrected reference').
symInfo(lowDp,s2,'Differential pressure below load-corrected reference').
symInfo(lowTopPurity,s3,'Distillate purity below specification').
symInfo(highBottomsImpurity,s4,'Light-key content in bottoms above reference').
symInfo(highTopTemp,s5,'Top temperature above reference (sensor judged reliable)').
symInfo(lowBottomTemp,s6,'Reboiler temperature below reference').
symInfo(highPressure,s7,'Top pressure above reference').
symInfo(lowPressure,s8,'Top pressure below reference').
symInfo(lowReflux,s9,'Reflux ratio below reference').
symInfo(lowBoilup,s10,'Reboiler duty below load-corrected reference').
symInfo(lowCondDuty,s11,'Condenser duty below load-corrected reference').
symInfo(massImbalance,s12,'Overall mass balance residual exceeds 5 percent').
symInfo(highBottomsLevel,s13,'Bottoms level above reference').
symInfo(lowDrumLevel,s14,'Reflux drum level below reference').
symInfo(coldFeed,s15,'Feed temperature below reference').
symInfo(highBoilup,s16,'Reboiler duty above load-corrected reference').
symInfo(instrumentConflict,s17,'Redundant measurements are mutually inconsistent').

% ---- Fault signatures: sig(Fault, CoreSymptoms, SupportSymptoms, RuleId)
sig(flooding,[highDp,lowTopPurity],[highBottomsLevel,highBottomsImpurity,highTopTemp],r1).
sig(weeping,[lowDp,lowTopPurity],[highBottomsImpurity],r2).
sig(entrainment,[lowTopPurity,highBoilup],[highDp],r3).
sig(foaming,[highDp,highBottomsLevel],[lowTopPurity],r4).
sig(fouling,[highDp,highBottomsImpurity],[lowBoilup],r5).
sig(condenser,[highPressure,lowCondDuty],[highTopTemp,lowDrumLevel],r6).
sig(reflux,[lowReflux,lowTopPurity],[highTopTemp,lowDrumLevel],r7).
sig(reboiler,[lowBoilup,lowBottomTemp],[highBottomsImpurity],r8).
sig(feed,[coldFeed],[lowBottomTemp],r9).
sig(pressureControl,[lowPressure],[],r10).
sig(leakage,[massImbalance,lowDrumLevel],[lowPressure],r11).
sig(instrumentation,[instrumentConflict],[],r12).

fname(flooding,'Column flooding').
fname(weeping,'Tray weeping or dumping').
fname(entrainment,'Excessive entrainment').
fname(foaming,'Foaming').
fname(fouling,'Tray or packing fouling').
fname(condenser,'Condenser degradation').
fname(reflux,'Reflux system fault').
fname(reboiler,'Reboiler or boilup fault').
fname(feed,'Feed condition abnormality').
fname(pressureControl,'Pressure control abnormality').
fname(leakage,'Leakage or containment loss').
fname(instrumentation,'Instrumentation fault').

% Consistency constraints: a fault is contradicted by observed symptoms it cannot produce.
excludes(flooding,lowDp). excludes(weeping,highDp). excludes(foaming,lowDp).
excludes(fouling,lowDp). excludes(fouling,lowTopPurity). excludes(condenser,lowPressure).
excludes(pressureControl,highPressure).

% ---- Maintenance rules: act(Fault, Class, Action, Precondition)
act(flooding,immediate,'Reduce feed rate and reboiler duty until differential pressure returns below the load-corrected limit.',true).
act(flooding,routine,'At the next shutdown inspect trays or packing for plugging, downcomer restriction and damaged internals.',true).
act(weeping,immediate,'Raise liquid-to-vapour ratio by increasing reflux or feed to restore tray hydraulic stability.',true).
act(weeping,routine,'Inspect tray decks, valves and weirs for damage or leakage paths.',true).
act(entrainment,immediate,'Reduce boilup to restore vapour velocity below the entrainment limit.',true).
act(entrainment,routine,'Inspect tray spacing, demister pads and downcomer sealing.',true).
act(foaming,immediate,'Reduce boilup and request approved antifoam dosing under process engineering authorisation.',true).
act(foaming,routine,'Analyse feed for surface-active contaminants and review antifoam programme.',true).
act(fouling,routine,'Schedule chemical or mechanical cleaning and inspect packing or trays for deposits.',true).
act(condenser,immediate,'Confirm relief device availability and reduce boilup while pressure is elevated.',sym(highPressure)).
act(condenser,routine,'Check cooling-water flow and temperature, then clean or retube the condenser.',true).
act(reflux,immediate,'Verify reflux pump operation and control valve position; restore the reflux ratio set point.',true).
act(reflux,routine,'Inspect reflux pump, flow transmitter and control valve trim.',true).
act(reboiler,immediate,'Verify heating-medium supply pressure and trap operation; restore boilup.',true).
act(reboiler,routine,'Inspect reboiler tube-side fouling and the steam control valve.',true).
act(feed,immediate,'Check feed preheater duty and feed temperature controller.',true).
act(feed,routine,'Inspect preheater exchanger and temperature transmitter.',true).
act(pressureControl,immediate,'Place the pressure controller in manual and confirm relief and vent path integrity.',true).
act(pressureControl,routine,'Calibrate the pressure transmitter and service the vent or condenser bypass valve.',true).
act(leakage,immediate,'Isolate suspected leak points under area safety procedure and verify containment.',true).
act(leakage,routine,'Perform flange, nozzle and exchanger tube-leak testing.',true).
act(instrumentation,routine,'Verify the flagged instrument against a reference, recalibrate, and avoid process moves based on the suspect reading.',true).

% ---- Reasoning
inL(L,X) :- memberchk(X,L).
lenIs(K,H) :- length(H,K).
explains(F,S) :- sig(F,C,Su,_), ( memberchk(S,C) ; memberchk(S,Su) ).
consistent(F,Ids) :- \+ ( excludes(F,S), memberchk(S,Ids) ).
consistentSet(Ids,H) :- forall(member(F,H), consistent(F,Ids)).
evOf(F,Ids,E,Emax) :- sig(F,Core,Sup,_), length(Core,NC), length(Sup,NS),
    include(inL(Ids),Core,CP), include(inL(Ids),Sup,SP), length(CP,A), length(SP,B),
    E is 2*A+B, Emax is 2*NC+NS.

% Abduction: choose fault sets whose explanations cover all observed symptoms (at most three faults).
abduce(_,[],H,H).
abduce(Al,[S|Ss],H0,H) :-
    (   member(F,H0), explains(F,S) -> abduce(Al,Ss,H0,H)
    ;   length(H0,L), L < 3, member(F,Al), explains(F,S), abduce(Al,Ss,[F|H0],H) ).
minimalIn(All,H) :- \+ ( member(H2,All), H2 \== H, subset(H2,H) ).
covers(Al,Ids,Cs) :-
    findall(H,(abduce(Al,Ids,[],H0),sort(H0,H)),L0), sort(L0,L1),
    include(minimalIn(L1),L1,L2), map_list_to_pairs(length,L2,Ps), keysort(Ps,Ks), pairs_values(Ks,Cs).

decide(Mode,Ids,Faults,Status) :-
    findall(E-F,(sig(F,Core,_,_),subset(Core,Ids),evOf(F,Ids,E,_),(Mode==deductive;consistent(F,Ids))),L0),
    sort(1,@>=,L0,L1), pairs_values(L1,CF),
    (   CF == [] -> fallback(Mode,Ids,Faults,Status)
    ;   Mode == deductive -> Faults = CF, Status = diagnosed
    ;   selectCover(CF,Ids,Faults,Status) ).
selectCover(CF,Ids,Faults,Status) :-
    covers(CF,Ids,Cs), Cs \== [], !,
    Cs = [H|_], length(H,K), include(lenIs(K),Cs,Best),
    (   Best = [Only] -> Faults = Only, Status = diagnosed
    ;   append(Best,A), sort(A,U), include(inL(U),CF,Faults), Status = ambiguous ).
selectCover(CF,_,CF,diagnosed).
fallback(Mode,Ids,Faults,hypothesis) :-
    Mode \== deductive, findall(F,sig(F,_,_,_),All), covers(All,Ids,Cs0),
    include(consistentSet(Ids),Cs0,Cs), Cs = [H|_], !,
    length(H,K), include(lenIs(K),Cs,Best), append(Best,A), sort(A,Faults).
fallback(_,_,[],inconclusive).

texts(L,Ts) :- findall(T,(member(S,L),symInfo(S,_,T)),Ts).
reason(F,_,Ids,R) :- excludes(F,S), memberchk(S,Ids), !, symInfo(S,_,T), format(atom(R),'Contradicted by observed evidence: ~w',[T]).
reason(_,Core,Ids,R) :- subtract(Core,Ids,M), M \== [], !, texts(M,Ts), atomic_list_concat(Ts,'; ',TT), format(atom(R),'Core evidence absent: ~w',[TT]).
reason(_,_,_,'Core evidence satisfied but redundant: explained by a smaller selected fault set').

diag(F,Ids,Faults,D) :-
    sig(F,Core,Sup,Rule), fname(F,Name), evOf(F,Ids,E,Em),
    include(inL(Ids),Core,CP), include(inL(Ids),Sup,SP), subtract(Core,Ids,Miss),
    findall(Ev,(member(Fx,Faults),evOf(Fx,Ids,Ev,_)),Es), sum_list(Es,Tot),
    M0 is E/Em, S0 is E/(Tot+0.001), r4(M0,M), r4(S0,Sh),
    findall(S,(member(S,Ids),explains(F,S)),Ex),
    D = _{id:F,name:Name,rule:Rule,core:CP,support:SP,missing:Miss,match:M,share:Sh,explains:Ex}.

rejected(Faults,Ids,Rej) :-
    findall(_{id:F,name:Name,reason:Re},
        ( sig(F,Core,Sup,_), \+ memberchk(F,Faults), fname(F,Name),
          append(Core,Sup,All), intersection(All,Ids,Hit), Hit \== [], reason(F,Core,Ids,Re) ), Rej).

plan(Faults,Plan) :-
    findall(_{fault:N,class:C,action:A},(member(F,Faults),act(F,C,A,P),C==immediate,call(P),fname(F,N)),I),
    findall(_{fault:N,class:C,action:A},(member(F,Faults),act(F,C,A,P),C==routine,call(P),fname(F,N)),R),
    append(I,R,Plan).

devs(L) :- findall(_{id:V,label:Lab,unit:U,value:X,ref:R,dev:E},
    ( ref(V,_,U,Lab), observation(V,X), effRef(V,R0), dev(V,E0), r4(R0,R), r4(E0,E) ), L).

% diagnose(+Obs, +Mode, -Result). Mode is full or deductive.
diagnose(Obs,Mode,D) :-
    get_time(T0), loadObs(Obs), length(Obs,N),
    findall(S,sym(S),I0), sort(I0,Ids),
    (   N < 8 -> Status = insufficient, Faults = []
    ;   Ids == [] -> Status = normal, Faults = []
    ;   decide(Mode,Ids,Faults,Status) ),
    findall(Fd,(member(F,Faults),diag(F,Ids,Faults,Fd)),Diags),
    rejected(Faults,Ids,Rej), plan(Faults,Plan), devs(Dv),
    findall(_{id:S,rule:R,text:T},(member(S,Ids),symInfo(S,R,T)),Sy),
    findall(_{id:C,text:T},conflict(C,T),Cf),
    findall(R,(member(S,Ids),symInfo(S,R,_)),SR), findall(R,(member(F,Faults),sig(F,_,_,R)),FR), append(SR,FR,Rules),
    get_time(T1), Ms0 is (T1-T0)*1000, r4(Ms0,Ms),
    D = _{status:Status,mode:Mode,nObs:N,timeMs:Ms,deviations:Dv,symptoms:Sy,conflicts:Cf,
          diagnoses:Diags,rejected:Rej,plan:Plan,faults:Faults,rulesFired:Rules}.

% ---- Knowledge base summary for the interface
kbSummary(D) :-
    findall(_{id:V,label:L,unit:U,ref:R},ref(V,R,U,L),Vars),
    findall(_{id:S,rule:Ru,text:T},symInfo(S,Ru,T),Syms),
    findall(_{id:F,name:N,rule:Ru,core:C,support:Su,excludes:Ex,actions:Acts},
        ( sig(F,C,Su,Ru), fname(F,N), findall(X,excludes(F,X),Ex),
          findall(_{class:K,text:A},act(F,K,A,_),Acts) ), Fs),
    D = _{variables:Vars,symptoms:Syms,faults:Fs}.

% ---- Validation suite (synthetic test cases; not plant measurements)
nominal([f-100.0,d-50.0,b-50.0,l-100.0,qr-1500.0,qc-1450.0,xd-0.98,xb-0.02,ttop-82.0,tbot-112.0,p-101.3,dp-6.0,tf-95.0,ldrum-50.0,lbot-50.0]).
upd(V-X,In,[V-X|R]) :- selectchk(V-_,In,R), !.
upd(V-X,In,[V-X|In]).
mk(Ch,Dr,Obs) :- nominal(N), foldl(upd,Ch,N,O1), exclude([V-_]>>memberchk(V,Dr),O1,Obs).

tc(t01,'Nominal operation',[normal],[],[]).
tc(t02,'High load, nominal behaviour',[normal],[f-120.0,d-60.0,b-60.0,l-120.0,qr-1800.0,qc-1740.0,dp-8.64],[]).
tc(t03,'Borderline pressure drop',[normal],[dp-7.5],[]).
tc(t04,'Noisy normal case',[normal],[f-101.0,xd-0.975,xb-0.021,ttop-82.8,tbot-111.5,p-101.9,dp-6.4],[]).
tc(t05,'Flooding',[flooding],[dp-9.5,xd-0.93,xb-0.05],[]).
tc(t06,'Weeping at low load',[weeping],[f-60.0,d-30.0,b-30.0,l-60.0,qr-900.0,qc-870.0,dp-1.2,xd-0.95,xb-0.06],[]).
tc(t07,'Entrainment',[entrainment],[xd-0.95,qr-1800.0],[]).
tc(t08,'Foaming',[foaming],[dp-9.5,lbot-70.0,xd-0.975],[]).
tc(t09,'Tray or packing fouling',[fouling],[dp-8.5,xb-0.035],[]).
tc(t10,'Condenser degradation',[condenser],[p-112.0,qc-1200.0,ttop-87.0],[]).
tc(t11,'Reflux system fault',[reflux],[l-70.0,xd-0.95,ttop-86.0],[]).
tc(t12,'Reboiler fault',[reboiler],[qr-1200.0,tbot-104.0,xb-0.035],[]).
tc(t13,'Cold feed',[feed],[tf-80.0],[]).
tc(t14,'Pressure control abnormality',[pressureControl],[p-90.0],[]).
tc(t15,'Leakage',[leakage],[b-44.0,ldrum-33.0],[]).
tc(t16,'Top temperature sensor fault',[instrumentation],[ttop-90.0],[]).
tc(t17,'Flow meter fault',[instrumentation],[b-40.0],[]).
tc(t18,'Multiple: flooding with cold feed',[flooding,feed],[dp-9.5,xd-0.93,xb-0.05,tf-80.0],[]).
tc(t19,'Ambiguous: flooding or foaming',[flooding,foaming],[dp-9.5,xd-0.93,lbot-70.0],[]).
tc(t20,'Incomplete: flooding, four sensors missing',[flooding],[dp-9.5,xd-0.93,xb-0.05],[ldrum,lbot,tf,qc]).
tc(t21,'Insufficient observations',[inconclusive],[],[f,d,b,l,qr,qc,xd,xb,ttop]).

labels(normal,_,[normal]) :- !.
labels(S,_,[inconclusive]) :- memberchk(S,[insufficient,inconclusive]), !.
labels(_,F,F).

runCase(Mode,tc(Id,Name,Exp,Ch,Dr),C) :-
    mk(Ch,Dr,Obs), diagnose(Obs,Mode,D),
    get_dict(status,D,St), get_dict(faults,D,F), get_dict(timeMs,D,Ms), get_dict(plan,D,Pl), get_dict(diagnoses,D,Dg),
    labels(St,F,Pred), sort(Exp,E1), sort(Pred,P1),
    ( E1 == P1 -> Ex = true ; Ex = false ),
    ( memberchk(St,[insufficient,inconclusive]) -> An = false ; An = true ),
    ( memberchk(St,[diagnosed,ambiguous,hypothesis]) -> FS = true ; FS = false ),
    ( FS == true, Pl \== [] -> PV = true ; PV = false ),
    ( An == true, ( St == normal ; Dg \== [] ) -> XP = true ; XP = false ),
    dict_pairs(OD,obs,Obs),
    C = _{id:Id,name:Name,expected:Exp,predicted:Pred,status:St,exact:Ex,answered:An,faultStatus:FS,planValid:PV,explained:XP,timeMs:Ms,obs:OD}.

cnt(Cs,K,N) :- aggregate_all(count,(member(C,Cs),get_dict(K,C,true)),N).
ratio(A,B,R) :- Bv is B, ( Bv =:= 0 -> R = 0.0 ; R0 is A/Bv, r4(R0,R) ).
f1(P,R,F) :- ( P+R =:= 0 -> F = 0.0 ; F0 is 2*P*R/(P+R), r4(F0,F) ).
tally(C,t(A,B,D),t(A1,B1,D1)) :-
    get_dict(expected,C,E), get_dict(predicted,C,P),
    intersection(E,P,I), length(I,X), subtract(P,E,PP), length(PP,Y), subtract(E,P,EE), length(EE,Z),
    A1 is A+X, B1 is B+Y, D1 is D+Z.
metrics(Cs,M) :-
    length(Cs,N), cnt(Cs,exact,Ex), cnt(Cs,answered,An), cnt(Cs,faultStatus,FSn), cnt(Cs,planValid,PV), cnt(Cs,explained,XP),
    foldl(tally,Cs,t(0,0,0),t(TP,FP,FN)),
    findall(T,(member(C,Cs),get_dict(timeMs,C,T)),Ts), sum_list(Ts,Sum), max_list(Ts,Max),
    ratio(Ex,N,Acc), ratio(An,N,Cov), ratio(TP,TP+FP,Pr), ratio(TP,TP+FN,Rc), f1(Pr,Rc,F1),
    ratio(XP,An,XR), ratio(PV,FSn,PVr), Mean0 is Sum/N, r4(Mean0,Mean), r4(Max,Mx),
    M = _{n:N,accuracy:Acc,coverage:Cov,precision:Pr,recall:Rc,f1:F1,meanMs:Mean,maxMs:Mx,explainRate:XR,planValidity:PVr}.

inb(X,L,true) :- memberchk(X,L).
inb(X,L,false) :- \+ memberchk(X,L).
cn(Cs,X,InE,InP,N) :- aggregate_all(count,(member(C,Cs),get_dict(expected,C,E),get_dict(predicted,C,P),inb(X,E,InE),inb(X,P,InP)),N).
perClass(Cs,L) :-
    findall(X,(member(C,Cs),(get_dict(expected,C,Es);get_dict(predicted,C,Es)),member(X,Es)),L0), sort(L0,Ls),
    findall(_{label:X,precision:P,recall:R,f1:F,support:S},
        ( member(X,Ls), cn(Cs,X,true,true,TP), cn(Cs,X,false,true,FP), cn(Cs,X,true,false,FN),
          ratio(TP,TP+FP,P), ratio(TP,TP+FN,R), f1(P,R,F), S is TP+FN ), L).
confusion(Cs,D) :-
    findall(A-P,(member(C,Cs),get_dict(expected,C,[A|_]),get_dict(predicted,C,Pp),(Pp=[P|_]->true;P=none)),Pairs),
    findall(X,(member(A-P,Pairs),(X=A;X=P)),L0), sort(L0,Ls),
    findall(Row,(member(A,Ls),findall(N,(member(P,Ls),aggregate_all(count,member(A-P,Pairs),N)),Row)),Mx),
    D = _{labels:Ls,matrix:Mx}.

runTests(D) :-
    findall(tc(I,N,E,Ch,Dr),tc(I,N,E,Ch,Dr),Ts),
    maplist(runCase(full),Ts,Cs), maplist(runCase(deductive),Ts,Cs2),
    metrics(Cs,M0), metrics(Cs2,M1),
    put_dict(mode,M0,'Complete system',M), put_dict(mode,M1,'Deductive reasoning only',Md),
    confusion(Cs,Cf), perClass(Cs,Pc),
    D = _{cases:Cs,metrics:M,ablation:[Md,M],confusion:Cf,perClass:Pc}.
