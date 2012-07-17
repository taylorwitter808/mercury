%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2007, 2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: interactive_query.m.
% Author: fjh.
%
% A module to invoke interactive queries using dynamic linking.
%
% This module reads in a query, writes out Mercury code for it to the file
% `mdb_query.m', invokes the Mercury compiler mmc to compile that file
% to `libmdb_query.so', dynamically loads in the object code for the module
% `mdb_query' from the file `libmdb_query.so', looks up the address of the
% procedure query/2 in that module, calls that procedure, and then
% cleans up the generated files.
%
%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- module mdb.interactive_query.
:- interface.

:- import_module io.
:- import_module list.

%-----------------------------------------------------------------------------%

:- pred query(query_type::in, imports::in, options::in,
    io.input_stream::in, io.output_stream::in, io::di, io::uo) is det.

    % query_external/7 is the same as query/7 but for the use
    % of the external debugger.
    %
:- pred query_external(query_type::in, imports::in, options::in,
    io.input_stream::in, io.output_stream::in, io::di, io::uo) is det.

:- type query_type
    --->    normal_query
    ;       cc_query
    ;       io_query.

:- type imports == list(string).
:- type options == string.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module mdb.dl.
:- import_module mdb.name_mangle.
:- import_module mdb.util.

:- import_module bool.
:- import_module maybe.
:- import_module parser.
:- import_module string.
:- import_module term.
:- import_module term_io.
:- import_module varset.

%-----------------------------------------------------------------------------%

:- pragma foreign_export("C", query(in, in, in, in, in, di, uo), "ML_query").

:- type prog
    --->    prog(query_type, imports, term, varset).

query(QueryType, Imports, Options, MDB_Stdin, MDB_Stdout, !IO) :-
    % write_import_list(Imports),
    util.trace_getline(query_prompt(QueryType), Result, MDB_Stdin, MDB_Stdout,
        !IO),
    (
        Result = eof,
        io.nl(MDB_Stdout, !IO)
    ;
        Result = error(Error),
        io.error_message(Error, Msg),
        io.write_string(MDB_Stdout, Msg, !IO),
        io.nl(MDB_Stdout, !IO),
        query(QueryType, Imports, Options, MDB_Stdin, MDB_Stdout, !IO)
    ;
        Result = ok(Line),
        parser.read_term_from_string("", Line, _, ReadTerm),
        query_2(QueryType, Imports, Options, MDB_Stdin, MDB_Stdout,
            ReadTerm, !IO)
    ).

:- pred query_2(query_type::in, imports::in, options::in,
    io.input_stream::in, io.output_stream::in, read_term(generic)::in,
    io::di, io::uo) is det.

query_2(QueryType, Imports, Options, MDB_Stdin, MDB_Stdout, ReadTerm, !IO) :-
    (
        ReadTerm = eof,
        io.nl(MDB_Stdout, !IO)
    ;
        ReadTerm = error(Msg, _Line),
        io.write_string(MDB_Stdout, Msg, !IO),
        io.nl(MDB_Stdout, !IO),
        query(QueryType, Imports, Options, MDB_Stdin, MDB_Stdout, !IO)
    ;
        ReadTerm = term(VarSet, Term),
        % io.write_string("Read term: "),
        % term_io.write_term(Term, VarSet),
        % io.write_string("\n"),
        (
            Term = term.functor(term.atom("quit"), [], _)
        ->
            io.nl(MDB_Stdout, !IO)
        ;
            Term = term.functor(term.atom("options"),
                [term.functor(term.string(NewOptions), [], _)], _)
        ->
            print(MDB_Stdout, "Compilation options: ", !IO),
            print(MDB_Stdout, NewOptions, !IO),
            io.nl(MDB_Stdout, !IO),
            query(QueryType, Imports, NewOptions, MDB_Stdin, MDB_Stdout, !IO)
        ;
            term_to_list(Term, ModuleList)
        ->
            list.append(Imports, ModuleList, NewImports),
            write_import_list(MDB_Stdout, NewImports, !IO),
            query(QueryType, NewImports, Options, MDB_Stdin, MDB_Stdout, !IO)
        ;
            % The flush ensures that all output generated by the debugger
            % up to this point appears in the output stream before any messages
            % generated by the compilation of the query, which is done
            % by another process.
            io.flush_output(MDB_Stdout, !IO),
            run_query(Options, prog(QueryType, Imports, Term, VarSet), !IO),
            query(QueryType, Imports, Options, MDB_Stdin, MDB_Stdout, !IO)
        )
    ).

    % interactive_query_response is type of the terms sent to the socket
    % during an interactive query session under the control of the
    % external debugger.

:- type interactive_query_response
    --->    iq_ok
    ;       iq_imported(imports)
    ;       iq_quit
    ;       iq_eof
    ;       iq_error(string).

:- pragma foreign_export("C", query_external(in, in, in, in, in, di, uo),
    "ML_query_external").

query_external(QueryType, Imports, Options, SocketIn, SocketOut, !IO) :-
    io.set_input_stream(SocketIn, OldStdin, !IO),
    term_io.read_term(Result, !IO),
    io.set_input_stream(OldStdin, _, !IO),
    (
        Result = eof,
        send_term_to_socket(iq_eof, SocketOut, !IO)
    ;
        Result = error(ErrorMsg, _Line),
        send_term_to_socket(iq_error(ErrorMsg), SocketOut, !IO),
        query_external(QueryType, Imports, Options, SocketIn, SocketOut, !IO)
    ;
        Result = term(VarSet, Term),
        (
            Term = term.functor(term.atom("quit"), [], _)
        ->
            send_term_to_socket(iq_quit, SocketOut, !IO)
        ;
            Term = term.functor(term.atom("options"),
                [term.functor(term.string(NewOptions), [], _)], _)
        ->
            send_term_to_socket(iq_ok, SocketOut, !IO),
            query_external(QueryType, Imports, NewOptions, SocketIn, SocketOut,
                !IO)
        ;
            term_to_list(Term, ModuleList)
        ->
            list.append(Imports, ModuleList, NewImports),
            send_term_to_socket(iq_imported(NewImports), SocketOut, !IO),
            query_external(QueryType, NewImports, Options, SocketIn, SocketOut,
                !IO)
        ;
            run_query(Options, prog(QueryType, Imports, Term, VarSet), !IO),
            send_term_to_socket(iq_ok, SocketOut, !IO),
            query_external(QueryType, Imports, Options, SocketIn, SocketOut,
                !IO)
        )
    ).

:- pred send_term_to_socket(interactive_query_response::in,
    io.output_stream::in, io::di, io::uo) is det.

send_term_to_socket(Term, SocketStream, !IO) :-
    write(SocketStream, Term, !IO),
    print(SocketStream, ".\n", !IO),
    flush_output(SocketStream, !IO).

:- func query_prompt(query_type) = string.

query_prompt(normal_query) = "?- ".
query_prompt(cc_query) = "?- ".
query_prompt(io_query) = "run <-- ".

:- pred term_to_list(term::in, list(string)::out) is semidet.

term_to_list(term.functor(term.atom("[]"), [], _), []).
term_to_list(term.functor(term.atom("[|]"),
        [term.functor(term.atom(Module), [], _C1), Rest], _C2),
        [Module | Modules]) :-
    term_to_list(Rest, Modules).

:- pred run_query(options::in, prog::in, io::di, io::uo) is det.

run_query(Options, Program, !IO) :-
    SourceFile = query_module_name ++ ".m",
    io.get_environment_var("MERCURY_OPTIONS", MaybeMercuryOptions, !IO),
    (
        MaybeMercuryOptions = yes(MercuryOptions),
        io.set_environment_var("MERCURY_OPTIONS", "", !IO),
        write_prog_to_file(Program, SourceFile, !IO),
        compile_file(Options, Succeeded, !IO),
        (
            Succeeded = yes,
            dynamically_load_and_run(!IO)
        ;
            Succeeded = no
        ),
        cleanup_query(Options, !IO),
        io.set_environment_var("MERCURY_OPTIONS", MercuryOptions, !IO)
    ;
        MaybeMercuryOptions = no,
        print("Unable to unset MERCURY_OPTIONS environment variable", !IO)
    ).

%-----------------------------------------------------------------------------%
%
% Print the program to a file
%

:- pred write_prog_to_file(prog::in, string::in, io::di, io::uo) is det.

write_prog_to_file(Program, FileName, !IO) :-
    open_output_file(FileName, Stream, !IO),
    io.set_output_stream(Stream, OldStream, !IO),
    write_prog_to_stream(Program, !IO),
    io.set_output_stream(OldStream, _, !IO),
    io.close_output(Stream, !IO).

:- pred open_output_file(string::in, io.output_stream::out,
    io::di, io::uo) is det.

open_output_file(File, Stream, !IO) :-
    io.open_output(File, Result, !IO),
    (
        Result = ok(Stream0),
        Stream = Stream0
    ;
        Result = error(Error),
        io.progname("interactive", Progname, !IO),
        io.error_message(Error, ErrorMessage),
        string.append_list([
            Progname, ": ",
            "error opening file `", File, "' for output:\n\t",
            ErrorMessage, "\n"],
            Message),
        io.write_string(Message, !IO),
        % XXX we really ought to throw an exception here;
        %     instead, we just return a bogus stream (stdout)
        io.stdout_stream(Stream, !IO)
    ).

:- pred write_prog_to_stream(prog::in, io::di, io::uo) is det.

write_prog_to_stream(prog(QueryType, Imports, Term, VarSet), !IO) :-
    io.write_string("
        :- module mdb_query.
        :- interface.
        :- import_module io.
        :- pred run(io.state::di, io.state::uo) is cc_multi.
        :- implementation.
        ", !IO),
    io.output_stream(Out, !IO),
    write_import_list(Out, ["solutions" | Imports], !IO),
    io.write_string("
            :- pragma source_file(""<stdin>"").
            run -->
    ", !IO),
    (
        QueryType = normal_query,
        term.vars(Term, Vars0),
        list.remove_dups(Vars0, Vars),

%   For a normal query, we generate code that looks like this:
%
%       run -->
%           unsorted_aggregate(
%               (pred(res(A,B,C)::out) is nondet :-
%                   query(A,B,C)),
%               (pred(res(A,B,C)::in, di, uo) is cc_multi -->
%                   print("A = "), print_cc(A), print(","),
%                   print("B = "), print_cc(B), print(","),
%                   print("C = "), print_cc(C), print(","),
%                   print("true ;\n"))
%           ),
%           print(""fail.\n""),
%           print(""No (more) solutions.\n"").
%
%       :- type res(A, B, C) ---> res(A, B, C).
%
%       % :- mode query(out, out, out) is nondet.
%       query(res(A, B, C)) :-
%               ...

        io.write_string("
            unsorted_aggregate(
                (pred(res", !IO),
        write_args(Vars, VarSet, !IO),
        io.write_string("::out) is nondet :-
            query", !IO),
        write_args(Vars, VarSet, !IO),
        io.write_string("),", !IO),
        io.write_string("(pred(res", !IO),
        write_args(Vars, VarSet, !IO),
        io.write_string("::in, di, uo) is cc_multi -->
            ", !IO),
        list.foldl(write_code_to_print_one_var(VarSet), Vars, !IO),
        io.write_string("
                    io.write_string(""true ;\n""))
                ),
                io.write_string(""fail.\n""),
                io.write_string(""No (more) solutions.\n"").

            :- type res", !IO),
        write_args(Vars, VarSet, !IO),
        io.write_string(" ---> res", !IO),
        write_args(Vars, VarSet, !IO),
        io.write_string(".\n", !IO),

%       io.write_string("
%           :- mode query"),
%       ( Vars \= [] ->
%           list.length(Vars, NumVars),
%           list.duplicate(NumVars, "out", Modes),
%           io.write_string("(", !IO),
%           io.write_list(Modes, ", ", io.write_string, !IO),
%           io.write_string(")", !IO)
%       ;
%           true
%       ),
%       io.write_string(" is nondet.", !IO),

        io.write_string("
            query", !IO),
        write_args(Vars, VarSet, !IO),
        io.write_string(" :- ", !IO),
        write_line_directive(!IO),
        term_io.write_term(VarSet, Term, !IO),
        io.write_string(" .\n", !IO)
    ;
        QueryType = cc_query,
        %
        % For a cc_query, we generate code that looks like this:
        %
        %   run --> if { query(A, B, C) } then
        %           print("A = "), print(A), print(", "),
        %           print("B = "), print(B), print(", "),
        %           print("C = "), print(C), print(", "),
        %           print("Yes.\n"))
        %       else
        %           print("No solution.\n").
        %
        %   query(A, B, C) :- ...
        %

        term.vars(Term, Vars0),
        list.remove_dups(Vars0, Vars),
        io.write_string("(if { query", !IO),
        write_args(Vars, VarSet, !IO),
        io.write_string(" } then\n", !IO),
        list.foldl(write_code_to_print_one_var(VarSet), Vars, !IO),
        io.write_string("
                    io.write_string(""true.\\n"")
                else
                    io.write_string(""No solution.\\n"")
                ).
        ", !IO),
        io.write_string("query", !IO),
        write_args(Vars, VarSet, !IO),
        io.write_string(" :-\n", !IO),
        write_line_directive(!IO),
        term_io.write_term(VarSet, Term, !IO),
        io.write_string(" .\n", !IO)
    ;
        QueryType = io_query,
        %
        % For an io_query, we just spit the code straight out:
        %
        %   run --> ...
        %
        write_line_directive(!IO),
        term_io.write_term(VarSet, Term, !IO),
        io.write_string(" .\n", !IO)
    ).

:- pred write_line_directive(io::di, io::uo) is det.

write_line_directive(!IO) :-
    io.write_string("\n#", !IO),
    io.get_line_number(LineNum, !IO),
    io.write_int(LineNum, !IO),
    io.nl(!IO).

:- pred write_code_to_print_one_var(varset::in, var::in,
    io::di, io::uo) is det.

write_code_to_print_one_var(VarSet, Var, !IO) :-
    io.write_string("io.write_string(""", !IO),
    term_io.write_variable(Var, VarSet, !IO),
    io.write_string(" = ""), io.write_cc(", !IO),
    term_io.write_variable(Var, VarSet, !IO),
    print("), io.write_string("", ""), ", !IO).

:- pred write_args(list(var)::in, varset::in, io::di, io::uo) is det.

write_args(Vars, VarSet, !IO) :-
    (
        Vars = [_ | _],
        io.write_string("(", !IO),
        io.write_list(Vars, ", ", write_one_var(VarSet), !IO),
        io.write_string(")", !IO)
    ;
        Vars = []
    ).

:- pred write_one_var(varset::in, var::in, io::di, io::uo) is det.

write_one_var(VarSet, Var, !IO) :-
    term_io.write_variable(Var, VarSet, !IO).

:- pred write_import_list(io.output_stream::in, imports::in,
    io::di, io::uo) is det.

write_import_list(Out, Imports, !IO) :-
    io.write_string(Out, ":- import_module ", !IO),
    io.write_list(Out, Imports, ", ", term_io.quote_atom, !IO),
    io.write_string(Out, ".\n", !IO).

%-----------------------------------------------------------------------------%
%
% Invoke the Mercury compile to compile the file to a shared object
%

:- pred compile_file(options::in, bool::out, io::di, io::uo) is det.

compile_file(Options, Succeeded, !IO) :-
    %
    % We use the following options:
    %   --grade
    %       make sure the grade of libmdb_query.so matches the
    %       grade of the executable it will be linked against
    %   --pic-reg
    %       needed for shared libraries / dynamic linking
    %   --infer-all
    %       for inferring the type etc. of query/N
    %   -O0 --no-c-optimize
    %       to improve compilation speed
    %   --no-verbose-make
    %       don't show which files are being made
    %   --output-compile-error-lines 10000
    %       output all errors
    %   --no-warn-det-decls-too-lax
    %   --no-warn-simple-code
    %       to avoid spurious warnings in the automatically
    %       generated parts of the query predicate
    %   --allow-undefined
    %       needed to allow the query to reference
    %       symbols defined in the program
    %
    string.append_list([
        "mmc --infer-all --no-verbose-make -O0 --no-c-optimize ",
        "--no-warn-simple-code --no-warn-det-decls-too-lax ",
        "--output-compile-error-lines 10000 ",
        "--allow-undefined ", Options,
        " --grade ", grade_option,
        " --pic-reg --compile-to-shared-lib ",
        query_module_name],
        Command),
    invoke_system_command(Command, Succeeded, !IO).

:- pred cleanup_query(options::in, io::di, io::uo) is det.

cleanup_query(_Options) -->
    io.remove_file(query_module_name ++ ".m", _),
    io.remove_file(query_module_name ++ ".d", _),
    io.remove_file("Mercury/ds/" ++ query_module_name ++ ".d", _),
    io.remove_file(query_module_name ++ ".c", _),
    io.remove_file("Mercury/cs/" ++ query_module_name ++ ".c", _),
    io.remove_file(query_module_name ++ ".c_date", _),
    io.remove_file("Mercury/c_dates/" ++ query_module_name ++ ".c_date",
        _),
    io.remove_file(query_module_name ++ ".o", _),
    io.remove_file("Mercury/os/" ++ query_module_name ++ ".o", _),
    io.remove_file("lib" ++ query_module_name ++ ".so", _).

:- func grade_option = string.
%
% `grade_option' returns MR_GRADE_OPT,
% which is defined in runtime/mercury_grade.h.
% This is a string containing the grade that the current
% executable was compiled in, in a form suitable for
% passing as a `--grade' option to mmc or ml.
%
:- pragma foreign_decl("C", "
    #include ""mercury_grade.h""
    #include ""mercury_string.h""
").
:- pragma foreign_proc("C",
    grade_option = (GradeOpt::out),
    [promise_pure, thread_safe, will_not_call_mercury],
"
    MR_make_aligned_string(GradeOpt, (MR_String) MR_GRADE_OPT);
").

grade_option = _ :-
    private_builtin.sorry("grade_option").

:- func verbose = bool.

verbose = no.

:- pred invoke_system_command(string::in, bool::out, io::di, io::uo) is det.

invoke_system_command(Command, Succeeded, !IO) :-
    ( verbose = yes ->
        io.write_string("% Invoking system command `", !IO),
        io.write_string(Command, !IO),
        io.write_string("'...\n", !IO),
        io.flush_output(!IO)
    ;
        true
    ),
    io.call_system(Command, Result, !IO),
    (
        Result = ok(Status),
        ( Status = 0 ->
            ( verbose = yes ->
                print("% done.\n", !IO)
            ;
                true
            ),
            Succeeded = yes
        ;
            print("Compilation error(s) occurred.\n", !IO),
            Succeeded = no
        )
    ;
        Result = error(_),
        print("Error: unable to invoke the compiler.\n", !IO),
        Succeeded = no
    ).

%-----------------------------------------------------------------------------%
%
% dynamically load the shared object and execute the query
%

:- func query_module_name = string.

query_module_name = "mdb_query".

:- pred dynamically_load_and_run(io::di, io::uo) is det.

dynamically_load_and_run(!IO) :-
    %
    % Load in the object code for the module `query' from
    % the file `libquery.so'.
    %
    dl.open("./lib" ++ query_module_name ++ ".so", lazy, local, MaybeHandle,
        !IO),
    (
        MaybeHandle = dl_error(Msg),
        print("dlopen failed: ", !IO),
        print(Msg, !IO),
        nl(!IO)
    ;
        MaybeHandle = dl_ok(Handle),
        %
        % Look up the address of the first mode (mode number 0)
        % of the predicate run/2 in the module query.
        %
        QueryProc = mercury_proc(predicate, unqualified(query_module_name),
            "run", 2, 0),
        dl.mercury_sym(Handle, QueryProc, MaybeQuery, !IO),
        (
            MaybeQuery = dl_error(Msg),
            print("dlsym failed: ", !IO),
            print(Msg, !IO),
            nl(!IO)
        ;
            MaybeQuery = dl_ok(QueryPred0),
            %
            % Cast the higher-order term that we obtained
            % to the correct higher-order inst.
            %
            QueryPred = inst_cast(QueryPred0),
            %
            % Call the procedure whose address
            % we just obtained.
            %
            QueryPred(!IO)
        ),
        %
        % unload the object code in the libquery.so file
        %
        dl.close(Handle, Result, !IO),
        (
            Result = dl_error(CloseMsg),
            print("dlclose failed: ", !IO),
            print(CloseMsg, !IO),
            nl(!IO)
        ;
            Result = dl_ok
        )
    ).

%
% dl.mercury_sym returns a higher-order term with inst `ground'.
% We need to cast it to the right higher-order inst, namely
% `pred(di, uo) is det' before we can actually call it.
% The function inst_cast/1 defined below does that.
%

:- type io_pred == pred(io, io).
:- inst io_pred == (pred(di, uo) is det).

:- func inst_cast(io_pred) = io_pred.
:- mode inst_cast(in) = out(io_pred) is det.

:- pragma foreign_proc("C",
    inst_cast(X::in) = (Y::out(io_pred)),
    [promise_pure, will_not_call_mercury, thread_safe],
"
    Y = X
").

inst_cast(_) = _ :-
    private_builtin.sorry("inst_cast").

%-----------------------------------------------------------------------------%