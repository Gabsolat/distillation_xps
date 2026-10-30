:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).
:- [engine].
:- dynamic appdir/1.
:- prolog_load_context(directory,D), asserta(appdir(D)).
:- initialization(main,main).

:- http_handler(root(api/diagnose), diagnoseH, [method(post)]).
:- http_handler(root(api/tests), testsH, []).
:- http_handler(root(api/kb), kbH, []).
:- http_handler(root(.), staticH, [prefix]).

diagnoseH(Req) :-
    http_read_json_dict(Req,In),
    ( get_dict(mode,In,M0) -> atom_string(Mode,M0) ; Mode = full ),
    ( get_dict(obs,In,O) -> dict_pairs(O,_,KVs) ; KVs = [] ),
    findall(K-V,(member(K-V,KVs),number(V),ref(K,_,_,_)),Obs),
    diagnose(Obs,Mode,D), reply_json_dict(D).
testsH(_) :- runTests(D), reply_json_dict(D).
kbH(_) :- kbSummary(D), reply_json_dict(D).
staticH(Req) :- appdir(D), directory_file_path(D,public,P),
    http_reply_from_files(P,[indexes(['index.html'])],Req).
staticH(Req) :- http_404([],Req).

main :-
    ( getenv('PORT',S) -> atom_number(S,Port) ; Port = 8080 ),
    http_server(http_dispatch,[port(Port)]),
    format(user_error,'Expert system listening on port ~w~n',[Port]),
    thread_get_message(shutdown).
