%-----------------------------------------------------------------------------%

% File: make_hlds.nl.
% Main author: fjh.

% This module converts from the parse tree structure which is
% read in by prog_io.nl, into the simplified high level data structure
% defined in hlds.nl.  In the parse tree, the program is represented
% as a list of items; we insert each item into the appropriate symbol
% table, and report any duplicate definition errors.  We also
% transform clause bodies from (A,B,C) into conj([A,B,C]) form.
%
% XXX we should return a flag indicating whether any errors
% occurred.

:- module make_hlds.
:- interface.
:- import_module prog_io, hlds.

:- pred parse_tree_to_hlds(program, module_info, io__state, io__state).
:- mode parse_tree_to_hlds(input, output, di, uo).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.
:- import_module prog_util, prog_out, require.

parse_tree_to_hlds(module(Name, Items), Module) -->
	{ moduleinfo_init(Name, Module0) },
	add_item_list_decls(Items, Module0, Module1),
	%%% { report_stats },
	add_item_list_clauses(Items, Module1, Module2),
	{ moduleinfo_predids(Module2, RevPredIds),
	  reverse(RevPredIds, PredIds),
	  moduleinfo_set_predids(Module2, PredIds, Module) }.

%-----------------------------------------------------------------------------%

	% add the declarations one by one to the module

:- pred add_item_list_decls(item_list, module_info, module_info,
				io__state, io__state).
:- mode add_item_list_decls(input, input, output, di, uo).

add_item_list_decls([], Module, Module) --> [].
add_item_list_decls([Item - Context | Items], Module0, Module) -->
	(add_item_decl(Item, Context, Module0, Module1) ->
		{ true }
	;
		io__stderr_stream(StdErr),
		io__set_output_stream(StdErr, OldStream),
		io__write_string("\n"),
		prog_out__write_context(Context),
		io__write_string("internal error in make_hlds.\n"),
		io__write_string("Failed to process the following item:\n"),
		io__write_anything(Item),
		io__write_string("\n"),
		io__set_output_stream(OldStream, _)
	),
	add_item_list_decls(Items, Module1, Module).

	% add the clauses one by one to the module

:- pred add_item_list_clauses(item_list, module_info, module_info,
				io__state, io__state).
:- mode add_item_list_clauses(input, input, output, di, uo).

add_item_list_clauses([], Module, Module) --> [].
add_item_list_clauses([Item - Context | Items], Module0, Module) -->
	(add_item_clause(Item, Context, Module0, Module1) ->
		{ true }
	;
		io__stderr_stream(StdErr),
		io__set_output_stream(StdErr, OldStream),
		io__write_string("\n"),
		prog_out__write_context(Context),
		io__write_string("internal error in make_hlds.\n"),
		io__write_string("Failed to process the following clause:\n"),
		io__write_anything(Item),
		io__write_string("\n"),
		io__set_output_stream(OldStream, _)
	),
	add_item_list_clauses(Items, Module1, Module).

%-----------------------------------------------------------------------------%

	% dispatch on the different types of items

:- pred add_item_decl(item, term__context, module_info, module_info,
			io__state, io__state).
:- mode add_item_decl(input, input, input, output, di, uo).

add_item_decl(clause(_, _, _, _), _, Module, Module) --> [].	% skip clauses

add_item_decl(type_defn(VarSet, TypeDefn, Cond), Context, Module0, Module) -->
	module_add_type_defn(Module0, VarSet, TypeDefn, Cond, Context, Module).

add_item_decl(inst_defn(VarSet, InstDefn, Cond), Context, Module0, Module) -->
	module_add_inst_defn(Module0, VarSet, InstDefn, Cond, Context, Module).

add_item_decl(mode_defn(VarSet, ModeDefn, Cond), Context, Module0, Module) -->
	module_add_mode_defn(Module0, VarSet, ModeDefn, Cond, Context, Module).

add_item_decl(pred(VarSet, PredName, TypesAndModes, Det, Cond), Context,
		Module0, Module) -->
	module_add_pred(Module0, VarSet, PredName, TypesAndModes, Det, Cond,
		Context, Module).

add_item_decl(mode(VarSet, PredName, Modes, Det, Cond), Context, Module0,
		Module) -->
	module_add_mode(Module0, VarSet, PredName, Modes, Det, Cond, Context,
		Module).

add_item_decl(module_defn(_VarSet, ModuleDefn), Context, Module, Module) -->
	( { ModuleDefn = interface } ->
		[]
	; { ModuleDefn = implementation } ->
		[]
	; { ModuleDefn = import(module(_)) } ->
		[]
	;
		io__stderr_stream(StdErr),
		io__set_output_stream(StdErr, OldStream),
		prog_out__write_context(Context),
		io__write_string("warning: declaration not yet implemented.\n"),
		io__set_output_stream(OldStream, _)
	).

add_item_decl(nothing, _, Module, Module) -->
	[].

%-----------------------------------------------------------------------------%

	% dispatch on the different types of items

:- pred add_item_clause(item, term__context, module_info, module_info,
			io__state, io__state).
:- mode add_item_clause(input, input, input, output, di, uo).

add_item_clause(clause(VarSet, PredName, Args, Body), Context, Module0,
			Module) -->
	module_add_clause(Module0, VarSet, PredName, Args, Body, Context,
			Module).
add_item_clause(type_defn(_, _, _), _, Module, Module) --> [].
add_item_clause(inst_defn(_, _, _), _, Module, Module) --> [].
add_item_clause(mode_defn(_, _, _), _, Module, Module) --> [].
add_item_clause(pred(_, _, _, _, _), _, Module, Module) --> [].
add_item_clause(mode(_, _, _, _, _), _, Module, Module) --> [].
add_item_clause(module_defn(_, _), _, Module, Module) --> [].
add_item_clause(nothing, _, Module, Module) --> [].

%-----------------------------------------------------------------------------%


:- pred module_add_inst_defn(module_info, varset, inst_defn, condition,
			term__context, module_info, io__state, io__state).
:- mode module_add_inst_defn(input, input, input, input, input, output, di, uo).

module_add_inst_defn(Module0, VarSet, InstDefn, Cond, Context, Module) -->
	{ moduleinfo_insts(Module0, Insts0) },
	insts_add(Insts0, VarSet, InstDefn, Cond, Context, Insts),
	{ moduleinfo_set_insts(Module0, Insts, Module) }.

	% XXX handle abstract insts

:- pred insts_add(inst_table, varset, inst_defn, condition, term__context,
			inst_table, io__state, io__state).
:- mode insts_add(input, input, input, input, input, output, di, uo).
insts_add(Insts0, VarSet, eqv_inst(Name, Args, Body), Cond, Context, Insts) -->
	{ length(Args, Arity),
	  I = hlds__inst_defn(VarSet, Args, eqv_inst(Body), Cond, Context) },
	(
		% some [I2]		% NU-Prolog inconsistency
		{ map__search(Insts0, Name - Arity, I2) }
	->
		{ Insts = Insts0 },
		(
			{ inst_is_compat(I, I2) }
		->
			duplicate_def_warning(Name, Arity, "inst", Context)
		;
			multiple_def_error(Name, Arity, "inst", Context)
		)
	;
		{ map__insert(Insts0, Name - Arity, I, Insts) }
	).

	% Two different inst definitions are compatible if
	% their mode parameters and their bodies are identical.
	% (This is perhaps more strict than it need be.)

:- pred inst_is_compat(hlds__inst_defn, hlds__inst_defn).
:- mode inst_is_compat(input, input).

inst_is_compat(hlds__inst_defn(_, Args, Body, _, _),
		hlds__inst_defn(_, Args, Body, _, _)).

	% XXX should be in hlds.nl.

:- pred make_predid(string, sym_name, int, pred_id).
:- mode make_predid(input, input, input, output).

make_predid(ModName, unqualified(Name), Arity, pred(ModName, Name, Arity)).
make_predid(_, qualified(ModName, Name), Arity, pred(ModName, Name, Arity)).

%-----------------------------------------------------------------------------%

:- pred module_add_mode_defn(module_info, varset, mode_defn, condition,
			term__context, module_info, io__state, io__state).
:- mode module_add_mode_defn(input, input, input, input, input, output, di, uo).

module_add_mode_defn(Module0, VarSet, ModeDefn, Cond, Context, Module) -->
	{ moduleinfo_modes(Module0, Modes0) },
	modes_add(Modes0, VarSet, ModeDefn, Cond, Context, Modes),
	{ moduleinfo_set_modes(Module0, Modes, Module) }.

:- pred modes_add(mode_table, varset, mode_defn, condition, term__context,
			mode_table, io__state, io__state).
:- mode modes_add(input, input, input, input, input, output, di, uo).

modes_add(Modes0, VarSet, eqv_mode(Name, Args, Body), Cond, Context, Modes) -->
	{ length(Args, Arity),
	  I = hlds__mode_defn(VarSet, Args, eqv_mode(Body), Cond, Context) },
	(
		% some [I2]		% NU-Prolog inconsistency
		{ map__search(Modes0, Name - Arity, I2) }
	->
		{ Modes = Modes0 },
		(
			{ mode_is_compat(I, I2) }
		->
			duplicate_def_warning(Name, Arity, "mode", Context)
		;
			multiple_def_error(Name, Arity, "mode", Context)
		)
	;
		{ map__insert(Modes0, Name - Arity, I, Modes) }
	).

:- pred mode_name_args(mode_defn, sym_name, list(inst_param), hlds__mode_body).
:- mode mode_name_args(input, output, output, output).

mode_name_args(eqv_mode(Name, Args, Body), Name, Args, eqv_mode(Body)).

:- pred mode_is_compat(hlds__mode_defn, hlds__mode_defn).
:- mode mode_is_compat(input, input).

mode_is_compat(hlds__mode_defn(_, Args, Body, _, _),
		hlds__mode_defn(_, Args, Body, _, _)).

%-----------------------------------------------------------------------------%

	% We allow more than one "definition" for a given type so
	% long all of them except one are actually just declarations,
	% e.g. `:- type t.', which is parsed as an type definition for
	% t which defines t as an abstract_type.

:- pred module_add_type_defn(module_info, varset, type_defn, condition,
			term__context, module_info, io__state, io__state).
:- mode module_add_type_defn(input, input, input, input, input, output, di, uo).

module_add_type_defn(Module0, VarSet, TypeDefn, Cond, Context, Module) -->
	{ moduleinfo_types(Module0, Types0) },
	{ type_name_args(TypeDefn, Name, Args, Body),
	  length(Args, Arity),
	  T = hlds__type_defn(VarSet, Args, Body, Cond, Context) },
	(
		% if there was an existing non-abstract definition for the type
		{ map__search(Types0, Name - Arity, T2) },
		{ T2 = hlds__type_defn(_, _, Body_2, _, _) },
		{ \+ (Body_2 = abstract_type) }
	->
		{ Module = Module0 },
	  	(
			% then if this definition was abstract, ignore it
			{ Body = abstract_type }
		->
			[]
		;
			% otherwise give a warning or an error
			{ type_is_compat(T, T2) }
		->
			duplicate_def_warning(Name, Arity, "type", Context)
		;
			multiple_def_error(Name, Arity, "type", Context)
		)
	;
		{ 
		  TypeId = Name - Arity,
		  map__set(Types0, TypeId, T, Types)
		},
		( %%% some [ConsList]
			{ Body = du_type(ConsList) }
		->
			{ moduleinfo_ctors(Module0, Ctors0) },
			ctors_add(ConsList, TypeId, Context, Ctors0, Ctors),
			{ moduleinfo_set_ctors(Module0, Ctors, Module1) }
		;
			{ Module1 = Module0 }
		),
		{ moduleinfo_set_types(Module1, Types, Module) },
		( { Body = uu_type(_) } ->
			io__stderr_stream(StdErr),
			io__set_output_stream(StdErr, OldStream),
			prog_out__write_context(Context),
			io__write_string(
		"warning: undiscriminated union types not yet implemented.\n"),
			io__set_output_stream(OldStream, _)
		;
			[]
		)
	).

:- pred type_name_args(type_defn, sym_name, list(type_param), hlds__type_body).
:- mode type_name_args(input, output, output, output).

type_name_args(du_type(Name, Args, Body), Name, Args, du_type(Body)).
type_name_args(uu_type(Name, Args, Body), Name, Args, uu_type(Body)).
type_name_args(eqv_type(Name, Args, Body), Name, Args, eqv_type(Body)).
type_name_args(abstract_type(Name, Args), Name, Args, abstract_type).

	% Two type definitions are compatible if they have exactly the
	% same argument lists and bodies.

:- pred type_is_compat(hlds__type_defn, hlds__type_defn).
:- mode type_is_compat(input, input).

type_is_compat( hlds__type_defn(_, Args, Body, _, _),
		hlds__type_defn(_, Args, Body, _, _)).

:- pred ctors_add(list(constructor), type_id, term__context, cons_table,
			cons_table, io__state, io__state).
:- mode ctors_add(input, input, input, input, output, di, uo).


ctors_add([], _TypeId, _Context, Ctors, Ctors) --> [].
ctors_add([Name - Args | Rest], TypeId, Context, Ctors0, Ctors) -->
	{ make_cons_id(Name, Args, TypeId, ConsId) },
	{ ConsDefn = hlds__cons_defn(Args, TypeId, Context) },
	( %%% some [ConsDefns0]
		{ map__search(Ctors0, ConsId, ConsDefns0) }
	->
		{ ConsDefns1 = ConsDefns0 }
	;
		{ ConsDefns1 = [] }
	),
	( { member(hlds__cons_defn(_, TypeId, _), ConsDefns1) } ->
		io__stderr_stream(StdErr),
		io__set_output_stream(StdErr, OldStream),
		prog_out__write_context(Context),
		io__write_string("error: constructor `"),
		make_hlds__write_cons_id(ConsId),
		io__write_string("' for type `"),
		make_hlds__write_type_id(TypeId),
		io__write_string("' multiply defined.\n"),
		io__set_output_stream(OldStream, _),
		{ ConsDefns2 = ConsDefns1 }
	;
		{ ConsDefns2 = [ConsDefn | ConsDefns1] }
	),
	{ map__set(Ctors0, ConsId, ConsDefns2, Ctors1) },
	ctors_add(Rest, TypeId, Context, Ctors1, Ctors).

:- pred make_cons_id(sym_name, list(type), type_id, cons_id).
:- mode make_cons_id(input, input, input, output).

make_cons_id(qualified(_Module, Name), Args, _TypeId, cons(Name, Arity)) :-
	length(Args, Arity).
make_cons_id(unqualified(Name), Args, _TypeId, cons(Name, Arity)) :-
	length(Args, Arity).

:- pred make_hlds__write_cons_id(cons_id, io__state, io__state).
:- mode make_hlds__write_cons_id(input, di, uo).

make_hlds__write_cons_id(cons(Name, Arity)) -->
	io__write_string(Name),
	io__write_string("/"),
	io__write_int(Arity).

	% XXX this is duplicated in typecheck.nl
	% Should be in hlds_out.nl or something.

:- pred make_hlds__write_type_id(type_id, io__state, io__state).
:- mode make_hlds__write_type_id(input, di, uo).

make_hlds__write_type_id(Name - Arity) -->
	prog_out__write_sym_name(Name),
	io__write_string("/"),
	io__write_int(Arity).

%-----------------------------------------------------------------------------%

:- pred module_add_pred(module_info, varset, sym_name, list(type_and_mode),
		determinism, condition, term__context, module_info,
		io__state, io__state).
:- mode module_add_pred(input, input, input, input, input, input, input, output,
		di, uo).

module_add_pred(Module0, VarSet, PredName, TypesAndModes, Det, Cond, Context,
		Module) -->
	{ split_types_and_modes(TypesAndModes, Types, MaybeModes) },
	preds_add(Module0, VarSet, PredName, Types, Cond, Context, Module1),
	(
		% some [Modes]
		{ MaybeModes = yes(Modes) }
	->
		module_add_mode(Module1, VarSet, PredName, Modes, Det, Cond,
			Context, Module)
	;
		{ Module = Module1 }
	).

:- pred preds_add(module_info, varset, sym_name, list(type),
		condition, term__context, module_info, io__state, io__state).
:- mode preds_add(input, input, input, input, input, input, output,
		di, uo).

preds_add(Module0, VarSet, Name, Types, Cond, Context, Module) -->
	{ moduleinfo_name(Module0, ModuleName) },
	{ moduleinfo_preds(Module0, Preds0) },
	{ length(Types, Arity),
	  map__init(Procs),
	  make_predid(ModuleName, Name, Arity, PredId),
	  clauses_info_init(Arity, ClausesInfo),
	  P = predicate(VarSet, Types, Cond, ClausesInfo, Procs, Context) },
	(
		% some [P2]
		{ map__search(Preds0, PredId, P2) }
	->
		{ Module = Module0 },
		(
			{ pred_is_compat(P, P2) }
		->
			duplicate_def_warning(Name, Arity, "pred", Context)
		;
			multiple_def_error(Name, Arity, "pred", Context)
		)
	;
		{ map__insert(Preds0, PredId, P, Preds) },
		{ moduleinfo_set_preds(Module0, Preds, Module1) },
		{ moduleinfo_predids(Module1, PredIds0) },
		{ moduleinfo_set_predids(Module1, [PredId | PredIds0],
				Module2) },
		{ moduleinfo_pred_name_index(Module2, PredNameIndex0) },
		{ unqualify_name(Name, UnqualifiedName) },
		{
			map__search(PredNameIndex0, UnqualifiedName, PredIdList)
		->
			map__set(PredNameIndex0, UnqualifiedName,
				[PredId | PredIdList], PredNameIndex)
		;
			map__insert(PredNameIndex0, UnqualifiedName,
				[PredId], PredNameIndex)
		},
		{ moduleinfo_set_pred_name_index(Module2, PredNameIndex,
				Module) }
	).

:- pred pred_is_compat(pred_info, pred_info).
:- mode pred_is_compat(input, input).

pred_is_compat(predicate(_, Types, _, _, _, _),
	       predicate(_, Types, _, _, _, _)).
 
%-----------------------------------------------------------------------------%

	% Add a mode declaration for a predicate.

:- pred module_add_mode(module_info, varset, sym_name, list(mode), determinism,
			condition, term__context, module_info,
			io__state, io__state).
:- mode module_add_mode(input, input, input, input, input, input, input, output,
			di, uo).

module_add_mode(Module0, VarSet, PredName, Modes, Det, Cond, Context, Module)
		-->
	{ moduleinfo_preds(Module0, Preds0) },
	{ moduleinfo_name(Module0, ModuleName) },
	pred_modes_add(Preds0, ModuleName, VarSet, PredName, Modes, Det, Cond,
			Context, Preds),
	{ moduleinfo_set_preds(Module0, Preds, Module) }.

:- pred pred_modes_add(pred_table, module_name, varset, sym_name, list(mode),
		determinism, condition, term__context, pred_table,
		io__state, io__state).
:- mode pred_modes_add(input, input, input, input, input, input, input,
		input, output, di, uo).

	% XXX we should store the mode varset and the mode condition
	% in the hlds - at the moment we just ignore those two arguments

pred_modes_add(Preds0, ModuleName, VarSet, PredName, Modes, Det, Cond,
		MContext, Preds) -->
	{ length(Modes, Arity),
	  make_predid(ModuleName, PredName, Arity, PredId) },
	(
		% some [P0]
		{ map__search(Preds0, PredId, P0) }
	->
		{ P0 = predicate(TVarSet, ArgTypes, TCond, Clauses, Procs0,
			TContext) },
			% XXX we should check that this mode declaration
			% isn't the same as an existing one
		{ next_mode_id(Procs0, ModeId) },
		{ procinfo_init(Modes, Det, MContext, NewProc) },
		{ map__insert(Procs0, ModeId, NewProc, Procs) },
		{ P = predicate(TVarSet, ArgTypes, TCond, Clauses, Procs,
			TContext) },
		{ map__set(Preds0, PredId, P, Preds) }
	;
		undefined_pred_error(PredName, Arity, MContext,	
			"mode declaration"),
		{ preds_add_implicit(Preds0, PredId, MContext, Preds1) },
		pred_modes_add(Preds1, ModuleName, VarSet, PredName,
				Modes, Det, Cond, MContext, Preds)
	).

	% Whenever there is a clause or mode declaration for an undeclared
	% predicate, we add an implicit declaration for that predicate.

:- pred preds_add_implicit(pred_table, pred_id, term__context, pred_table).
:- mode preds_add_implicit(input, input, input, output).

preds_add_implicit(Preds0, PredId, Context, Preds) :-
	predicate_arity(PredId, Arity),
	clauses_info_init(Arity, ClausesInfo),
	map__init(Procs),
	varset__init(TVarSet0),
	make_n_fresh_vars(Arity, TVarSet0, TypeVars, TVarSet),
	var_list_to_term_list(TypeVars, Types),
	P = predicate(TVarSet, Types, true, ClausesInfo, Procs, Context),
	map__set(Preds0, PredId, P, Preds).

:- pred var_list_to_term_list(list(var), list(term)).
:- mode var_list_to_term_list(input, output) is det.
:- mode var_list_to_term_list(output, input).

var_list_to_term_list([], []).
var_list_to_term_list([V | Vs0], [term_variable(V) | Vs]) :-
	var_list_to_term_list(Vs0, Vs).

	% XXX efficiency could be improved
	% we should probably store the next available ModeId rather
	% than recomputing it all the time

:- pred next_mode_id(proc_table, proc_id).
:- mode next_mode_id(input, output).

next_mode_id(Procs, ModeId) :-
	map__to_assoc_list(Procs, List),
	length(List, ModeId).

%-----------------------------------------------------------------------------%

:- pred module_add_clause(module_info, varset, sym_name, list(term), goal,
			term__context, module_info, io__state, io__state).
:- mode module_add_clause(input, input, input, input, input, input, output,
			di, uo).

module_add_clause(Module0, VarSet, PredName, Args, Body, Context, Module) -->
	{ moduleinfo_preds(Module0, Preds0) },
	{ moduleinfo_name(Module0, ModuleName) },
	clauses_add(Preds0, ModuleName, VarSet, PredName, Args, Body, Context,
		Preds),
	{ moduleinfo_set_preds(Module0, Preds, Module) }.

:- pred clauses_add(pred_table, module_name, varset, sym_name, list(term),
			goal, term__context, pred_table, io__state, io__state).
:- mode clauses_add(input, input, input, input, input, input, input, output,
			di, uo).

clauses_add(Preds0, ModuleName, VarSet, PredName, Args, Body, Context,
		Preds) -->
	{ length(Args, Arity) },
	{ make_predid(ModuleName, PredName, Arity, PredId) },
	(
		% some [PredInfo0]
		{ map__search(Preds0, PredId, PredInfo0) }
	->
			% XXX abstract predicate/4
		{ PredInfo0 = predicate(TVarSet, Types, Cond, Clauses0, Procs,
				TContext),
		  map__keys(Procs, ModeIds),
		  clauses_info_add_clause(Clauses0, ModeIds, VarSet, Args,
				Body, Context, Clauses),
		  PredInfo = predicate(TVarSet, Types, Cond, Clauses, Procs,
				TContext),
		  map__set(Preds0, PredId, PredInfo, Preds) }
	;
		undefined_pred_error(PredName, Arity, Context, "clause"),
		{ preds_add_implicit(Preds0, PredId, Context, Preds1) },
		clauses_add(Preds1, ModuleName, VarSet, PredName, Args,
			Body, Context, Preds)
	).

:- pred clauses_info_init(int::in, clauses_info::out) is det.

clauses_info_init(Arity, clauses_info(VarSet, VarTypes, HeadVars, [])) :-
	map__init(VarTypes),
	varset__init(VarSet0),
	make_n_fresh_vars(Arity, VarSet0, HeadVars, VarSet).

:- pred clauses_info_add_clause(clauses_info::in,
		list(proc_id)::in, varset::in, list(term)::in, goal::in,
		term__context::in, clauses_info::out) is det.

clauses_info_add_clause(ClausesInfo0, ModeIds, CVarSet, Args, Body,
		Context, ClausesInfo) :-
	ClausesInfo0 = clauses_info(VarSet0, VarTypes, HeadVars, ClauseList0),
	varset__merge_subst(VarSet0, CVarSet, VarSet1, Subst),
	transform(Subst, HeadVars, Args, Body, VarSet1, Goal, VarSet),
		% XXX we should avoid append - this gives O(N*N)
	append(ClauseList0, [clause(ModeIds, Goal, Context)], ClauseList),
	ClausesInfo = clauses_info(VarSet, VarTypes, HeadVars, ClauseList).

:- pred transform(substitution, list(var), list(term), goal, varset,
			hlds__goal, varset).
:- mode transform(input, input, input, input, input, output, output) is det.

transform(Subst, HeadVars, Args0, Body, VarSet0, Goal, VarSet) :-
	transform_goal(Body, VarSet0, Subst, Goal1, VarSet1),
	term__apply_substitution_to_list(Args0, Subst, Args),
	insert_head_unifications(HeadVars, Args, head, Goal1, VarSet1,
		Goal, VarSet).

:- pred make_n_fresh_vars(int, varset, list(var), varset).
:- mode make_n_fresh_vars(input, input, output, output).

make_n_fresh_vars(N, VarSet0, Vars, VarSet) :-
	make_n_fresh_vars_2(0, N, VarSet0, Vars, VarSet).

:- pred make_n_fresh_vars_2(int, int, varset, list(var), varset).
:- mode make_n_fresh_vars_2(input, input, input, output, output).

make_n_fresh_vars_2(N, Max, VarSet0, Vars, VarSet) :-
	(N = Max ->
		VarSet = VarSet0,
		Vars = []
	;
		N1 is N + 1,
		varset__new_var(VarSet0, Var, VarSet1),
		%%% string__int_to_string(N1, Num),
		%%% string__append("HeadVar__", Num, VarName),
		%%% varset__name_var(VarSet1, Var, VarName, VarSet2),
		Vars = [Var | Vars1],
		make_n_fresh_vars_2(N1, Max, VarSet1, Vars1, VarSet)
	).

:- type head_context ---> head ; call(pred_id).

:- pred insert_head_unifications(list(var), list(term), head_context,
				hlds__goal, varset, hlds__goal, varset).
:- mode insert_head_unifications(input, input, input, input, input, 
				output, output).

insert_head_unifications(HeadVars, Args, HeadContext, Goal0, VarSet0,
			Goal, VarSet) :-
	( HeadVars = [] ->
		Goal = Goal0,
		VarSet = VarSet0
	;
		insert_head_unifications_2(HeadVars, Args, HeadContext, 0,
			[Goal0], VarSet0, List, VarSet),
		goalinfo_init(GoalInfo),
		Goal = conj(List) - GoalInfo
	).

:- pred insert_head_unifications_2(list(var), list(term), head_context, int,
				list(hlds__goal), varset,
				list(hlds__goal), varset).
:- mode insert_head_unifications_2(input, input, input, input, input, input,
				output, output).

insert_head_unifications_2([], [], _, _, List, VarSet, List, VarSet).
insert_head_unifications_2([Var|Vars], [Arg|Args], Context, N0, List0, VarSet0,
				List, VarSet) :-
	N1 is N0 + 1,
	Goal = unify(Arg, term_variable(Var), Mode, UnifyInfo, UnifyC) -
		GoalInfo,
	goalinfo_init(GoalInfo),
	head_context_to_unify_context(Context, N1, UnifyMainContext),
	UnifyC = unify_context(UnifyMainContext, []),
		% fill in unused slots with garbage values
	Mode = ((free -> free) - (free -> free)),
	UnifyInfo = complicated_unify(Mode, Arg, term_variable(Var)),
	List = [Goal | List1],
	insert_head_unifications_2(Vars, Args, Context, N1, List0, VarSet0,
				List1, VarSet).

:- pred head_context_to_unify_context(head_context, int, unify_main_context).
:- mode head_context_to_unify_context(input, input, output) is det.

head_context_to_unify_context(head, N, head(N)).
head_context_to_unify_context(call(PredId), N, call(PredId, N)).

:- pred transform_goal(goal, varset, substitution, hlds__goal, varset).
:- mode transform_goal(input, input, input, output, output).

transform_goal(fail, VarSet, _, disj([]) - GoalInfo, VarSet) :-
	goalinfo_init(GoalInfo).

transform_goal(true, VarSet, _, conj([]) - GoalInfo, VarSet) :-
	goalinfo_init(GoalInfo).

transform_goal(some(Vars0, Goal0), VarSet0, Subst,
		some(Vars, Goal) - GoalInfo, VarSet) :-
	substitute_vars(Vars0, Subst, Vars),
	transform_goal(Goal0, VarSet0, Subst, Goal, VarSet),
	goalinfo_init(GoalInfo).

transform_goal(all(Vars0, Goal0), VarSet0, Subst,
		all(Vars, Goal) - GoalInfo, VarSet) :-
	substitute_vars(Vars0, Subst, Vars),
	transform_goal(Goal0, VarSet0, Subst, Goal, VarSet),
	goalinfo_init(GoalInfo).

transform_goal(if_then_else(Vars0, A0, B0, C0), VarSet0, Subst,
		if_then_else(Vars, A, B, C) - GoalInfo, VarSet) :-
	substitute_vars(Vars0, Subst, Vars),
	transform_goal(A0, VarSet0, Subst, A, VarSet1),
	transform_goal(B0, VarSet1, Subst, B, VarSet2),
	transform_goal(C0, VarSet2, Subst, C, VarSet),
	goalinfo_init(GoalInfo).

transform_goal(if_then(Vars0, A0, B0), Subst, VarSet0, Goal, VarSet) :-
	transform_goal(if_then_else(Vars0, A0, B0, fail), Subst, VarSet0,
		Goal, VarSet).

transform_goal(not(Vars0, A0), VarSet0, Subst,
		not(Vars, A) - GoalInfo, VarSet) :-
	substitute_vars(Vars0, Subst, Vars),
	transform_goal(A0, VarSet0, Subst, A, VarSet),
	goalinfo_init(GoalInfo).

transform_goal((A0,B0), VarSet0, Subst, conj(L) - GoalInfo, VarSet) :-
	get_conj(B0, Subst, [], VarSet0, L0, VarSet1),
	get_conj(A0, Subst, L0, VarSet1, L, VarSet),
	goalinfo_init(GoalInfo).

transform_goal((A0;B0), VarSet0, Subst, disj(L) - GoalInfo, VarSet) :-
	get_disj(B0, Subst, [], VarSet0, L0, VarSet1),
	get_disj(A0, Subst, L0, VarSet1, L, VarSet),
	goalinfo_init(GoalInfo).

transform_goal(call(Goal0), VarSet0, Subst, Goal, VarSet) :-

	% fill unused slots with any old junk 
	ModeId = 0,
	Builtin = not_builtin,

	% XXX serious design flaw
	% XXX we need to know the module name!!!
	ModuleName = "xxx",

	term__apply_substitution(Goal0, Subst, Goal1),
	( Goal1 = term_functor(term_atom(PredName0), Args0, _) ->
		PredName = PredName0,
		Args = Args0
	;
		% If the called term is not an atom, then it is
		% either a variable, or something stupid like a number.
		% In the first case, we want to transform it to a call
		% to builtin:call/1, and in the latter case, we
		% In either case, we transform it to a call to call/1.
		% The latter case will will be caught by the type-checker.
		PredName = "call",
		Args = [Goal1]
	),
	length(Args, Arity),
	make_predid(ModuleName, unqualified(PredName), Arity, PredId),
	make_n_fresh_vars(Arity, VarSet0, HeadVars, VarSet1),
	var_list_to_term_list(HeadVars, HeadArgs),
	Goal2 = call(PredId, ModeId, HeadArgs, Builtin) - GoalInfo,
	goalinfo_init(GoalInfo),
	insert_head_unifications(HeadVars, Args, call(PredId), Goal2,
		VarSet0, Goal, VarSet).

transform_goal(unify(A0, B0), VarSet, Subst,
		unify(A, B, Mode, UnifyInfo, UnifyC) - GoalInfo, VarSet) :-
	term__apply_substitution(A0, Subst, A),
	term__apply_substitution(B0, Subst, B),
	goalinfo_init(GoalInfo),
	UnifyC = unify_context(explicit, []),
		% fill in unused slots with garbage values
	Mode = ((free -> free) - (free -> free)),
	UnifyInfo = complicated_unify(Mode, A, B).

% substitute_vars(Vars0, Subst, Vars)
%	apply substitiution `Subst' (which must only rename vars) to `Vars0',
%	and return the result in `Vars'.

:- pred substitute_vars(list(var), substitution, list(var)).
:- mode substitute_vars(input, input, output) is det.

substitute_vars([], _, []).
substitute_vars([Var0 | Vars0], Subst, [Var | Vars]) :-
	term__apply_substitution(term_variable(Var0), Subst, Term),
	Term = term_variable(Var),
	substitute_vars(Vars0, Subst, Vars).

% get_conj(Goal, Conj0, Subst, Conj) :
% 	Goal is a tree of conjuncts.  Flatten it into a list (applying Subst),
%	append Conj0, and return the result in Conj.

:- pred get_conj(goal, substitution, list(hlds__goal), varset,
		list(hlds__goal), varset).
:- mode get_conj(input, input, input, input, output, output).

get_conj(Goal, Subst, Conj0, VarSet0, Conj, VarSet) :-
	(
		%some [A,B]
		Goal = (A,B)
	->
		get_conj(B, Subst, Conj0, VarSet0, Conj1, VarSet1),
		get_conj(A, Subst, Conj1, VarSet1, Conj, VarSet)
	;
		transform_goal(Goal, VarSet0, Subst, Goal1, VarSet),
		Conj = [Goal1 | Conj0]
	).

% get_disj(Goal, Subst, Disj0, Disj) :
% 	Goal is a tree of disjuncts.  Flatten it into a list (applying Subst)
%	append Disj0, and return the result in Disj.

:- pred get_disj(goal, substitution, list(hlds__goal), varset,
		list(hlds__goal), varset).
:- mode get_disj(input, input, input, input, output, output).

get_disj(Goal, Subst, Disj0, VarSet0, Disj, VarSet) :-
	(
		%some [A,B]
		Goal = (A;B)
	->
		get_disj(B, Subst, Disj0, VarSet0, Disj1, VarSet1),
		get_disj(A, Subst, Disj1, VarSet1, Disj, VarSet)
	;
		transform_goal(Goal, VarSet0, Subst, Goal1, VarSet),
		Disj = [Goal1 | Disj0]
	).

%-----------------------------------------------------------------------------%

	% Predicates to write out the different warning and error messages.

:- pred duplicate_def_warning(sym_name, int, string, term__context,
				io__state, io__state).
:- mode duplicate_def_warning(input, input, input, input, di, uo).

duplicate_def_warning(Name, Arity, DefType, Context) -->
	prog_out__write_context(Context),
	io__write_string("warning: duplicate definition for "),
	io__write_string(DefType),
	io__write_string(" `"),
	prog_out__write_sym_name(Name),
	io__write_string("/"),
	io__write_int(Arity),
	io__write_string("'\n").

:- pred multiple_def_error(sym_name, int, string, term__context,
				io__state, io__state).
:- mode multiple_def_error(input, input, input, input, di, uo).

multiple_def_error(Name, Arity, DefType, Context) -->
	prog_out__write_context(Context),
	io__write_string("error: "),
	io__write_string(DefType),
	io__write_string(" `"),
	prog_out__write_sym_name(Name),
	io__write_string("/"),
	io__write_int(Arity),
	io__write_string("' multiply defined\n").

:- pred undefined_pred_error(sym_name, int, term__context, string,
				io__state, io__state).
:- mode undefined_pred_error(input, input, input, input, di, uo).

undefined_pred_error(Name, Arity, Context, Description) -->
	prog_out__write_context(Context),
	io__write_string("error: "),
	io__write_string(Description),
	io__write_string(" for `"),
	prog_out__write_sym_name(Name),
	io__write_string("/"),
	io__write_int(Arity),
	io__write_string("' without preceding pred declaration\n").

%-----------------------------------------------------------------------------%
