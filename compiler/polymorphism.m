%-----------------------------------------------------------------------------%
% Copyright (C) 1995 University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% file: polymorphism.m
% main author: fjh

% This module is a pass over the HLDS.
% It does a syntactic transformation to implement polymorphism
% using higher-order predicates.  Every polymorphic predicate is transformed
% so that it takes one additional argument for every type variable in the
% predicate's type declaration.  The argument is a type_info structure,
% which contains higher-order predicate variables for each of the builtin
% polymorphic operations (currently unification, compare/3, and index/2).
%
% The type_info structure is laid out as follows:
%
%	word 0		<arity of type constructor>
%			e.g. 0 for `int', 1 for `list(T)', 2 for `map(K, V)'.
%	word 1		<=/2 predicate for type>
%	word 2		<index/2 predicate for type>
%	word 3		<compare/3 predicate for type>
%	word 4+		<the type_infos for the type params>
%
% For example, we translate
%
%	:- pred p(T1).
%	:- pred q(T2).
%	:- pred r(T3).
%
%	p(X) :- q([X]), r(0).
%
% into
%
%	:- pred p(T1, pred(T1, T1)).
%	:- pred q(T2, pred(T2, T2)).
%	:- pred r(T3, pred(T2, T2)).
%
%	p(X, TypeInfo) :-
%		q([X], type_info(1, list_unify, list_index, list_compare,
%				TypeInfo)),
%		r(0, type_info(0, int_unify, int_index, int_compare)).
%
% (except that both the input and output of the transformation are
% actually in super-homogeneous form).

%-----------------------------------------------------------------------------%

:- module polymorphism.
:- interface. 
:- import_module hlds.

:- pred polymorphism__process_module(module_info, module_info).
:- mode polymorphism__process_module(in, out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.
:- import_module int, string, list, set, map, term, varset, std_util, require.
:- import_module prog_io, type_util, mode_util, quantification.
:- import_module code_util, unify_proc.

%-----------------------------------------------------------------------------%

	% This whole section just traverses the module structure.
	% We do two passes, the first to fix up the procedure bodies,
	% (and in fact everything except the pred_info argtypes),
	% the second to fix up the pred_info argtypes.
	% The reason we need two passes is that the first pass looks at
	% the argtypes of the called predicates, and so we need to make
	% sure we don't muck them up before we've finished the first pass.

polymorphism__process_module(ModuleInfo0, ModuleInfo) :-
	module_info_preds(ModuleInfo0, Preds),
	map__keys(Preds, PredIds),
	polymorphism__process_preds(PredIds, ModuleInfo0, ModuleInfo1),
	polymorphism__fixup_preds(PredIds, ModuleInfo1, ModuleInfo).

:- pred polymorphism__process_preds(list(pred_id), module_info, module_info).
:- mode polymorphism__process_preds(in, in, out) is det.

polymorphism__process_preds([], ModuleInfo, ModuleInfo).
polymorphism__process_preds([PredId | PredIds], ModuleInfo0, ModuleInfo) :-
	module_info_pred_info(ModuleInfo0, PredId, PredInfo),
	pred_info_name(PredInfo, PredName),
	( PredName = "call" ->
		ModuleInfo1 = ModuleInfo0
	;
		pred_info_procids(PredInfo, ProcIds),
		polymorphism__process_procs(PredId, ProcIds, ModuleInfo0,
			ModuleInfo1)
	),
	polymorphism__process_preds(PredIds, ModuleInfo1, ModuleInfo).

:- pred polymorphism__process_procs(pred_id, list(proc_id),
					module_info, module_info).
:- mode polymorphism__process_procs(in, in, in, out) is det.

polymorphism__process_procs(_PredId, [], ModuleInfo, ModuleInfo).
polymorphism__process_procs(PredId, [ProcId | ProcIds], ModuleInfo0,
		ModuleInfo) :-
	module_info_preds(ModuleInfo0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo0),
	pred_info_procedures(PredInfo0, ProcTable0),
	map__lookup(ProcTable0, ProcId, ProcInfo0),
	polymorphism__process_proc(ProcInfo0, PredInfo0, ModuleInfo0,
					ProcInfo, PredInfo1),
	map__set(ProcTable0, ProcId, ProcInfo, ProcTable),
	pred_info_set_procedures(PredInfo1, ProcTable, PredInfo),
	map__set(PredTable0, PredId, PredInfo, PredTable),
	module_info_set_preds(ModuleInfo0, PredTable, ModuleInfo1),
	polymorphism__process_procs(PredId, ProcIds, ModuleInfo1, ModuleInfo).

%---------------------------------------------------------------------------%

:- pred polymorphism__fixup_preds(list(pred_id), module_info, module_info).
:- mode polymorphism__fixup_preds(in, in, out) is det.

polymorphism__fixup_preds([], ModuleInfo, ModuleInfo).
polymorphism__fixup_preds([PredId | PredIds], ModuleInfo0, ModuleInfo) :-
	%
	% Recompute the arg types by finding the headvars and the var->type
	% mapping (from the first procedure for the predicate) and
	% applying the type mapping to the extra headvars to get the new
	% arg types.  Note that we are careful to only apply the mapping
	% to the extra head vars, not to the originals, because otherwise
	% we would stuff up the arg types for unification predicates for
	% equivalence types.
	%
	module_info_preds(ModuleInfo0, PredTable0),
	map__lookup(PredTable0, PredId, PredInfo0),
	pred_info_procedures(PredInfo0, ProcTable0),
	pred_info_procids(PredInfo0, ProcIds),
	( ProcIds = [ProcId|_] ->
		map__lookup(ProcTable0, ProcId, ProcInfo),
		proc_info_vartypes(ProcInfo, VarTypes),
		proc_info_headvars(ProcInfo, HeadVars),
		pred_info_arg_types(PredInfo0, TypeVarSet, ArgTypes0),
		list__length(ArgTypes0, NumOldArgs),
		list__length(HeadVars, NumNewArgs),
		NumExtraArgs is NumNewArgs - NumOldArgs,
		(
			list__split_list(NumExtraArgs, HeadVars, ExtraHeadVars,
					_OldHeadVars)
		->
			map__apply_to_list(ExtraHeadVars, VarTypes,
				ExtraArgTypes),
			list__append(ExtraArgTypes, ArgTypes0, ArgTypes)
		;
			error("polymorphism.m: list__split_list failed")
		),

		pred_info_set_arg_types(PredInfo0, TypeVarSet, ArgTypes,
			PredInfo),
		map__set(PredTable0, PredId, PredInfo, PredTable),
		module_info_set_preds(ModuleInfo0, PredTable, ModuleInfo1),
		polymorphism__fixup_preds(PredIds, ModuleInfo1, ModuleInfo)
	;
		ModuleInfo = ModuleInfo0
	).

%---------------------------------------------------------------------------%

:- type poly_info --->
		poly_info(
			varset,			% from the proc_info
			map(var, type),		% from the proc_info
			tvarset,		% from the proc_info
			map(tvar, var),		% specifies the type_info var
						% for each of the pred's type
						% parameters
			module_info
		).
	
:- pred polymorphism__process_proc(proc_info, pred_info, module_info,
					proc_info, pred_info).
:- mode polymorphism__process_proc(in, in, in, out, out) is det.

polymorphism__process_proc(ProcInfo0, PredInfo0, ModuleInfo,
					ProcInfo, PredInfo) :-
	% grab the appropriate fields from the pred_info and proc_info
	pred_info_arg_types(PredInfo0, ArgTypeVarSet, ArgTypes),
	pred_info_typevarset(PredInfo0, TypeVarSet0),
	proc_info_headvars(ProcInfo0, HeadVars0),
	proc_info_variables(ProcInfo0, VarSet0),
	proc_info_vartypes(ProcInfo0, VarTypes0),
	proc_info_goal(ProcInfo0, Goal0),
	proc_info_argmodes(ProcInfo0, ArgModes0),
	% insert extra head variables to hold the address of the
	% equality predicate for each polymorphic type in the predicate's
	% type declaration
	term__vars_list(ArgTypes, HeadTypeVars0),
	list__remove_dups(HeadTypeVars0, HeadTypeVars), % remove duplicates
	polymorphism__make_head_vars(HeadTypeVars, ArgTypeVarSet,
					VarSet0, VarTypes0,
				ExtraHeadVars, VarSet1, VarTypes1),
	list__append(ExtraHeadVars, HeadVars0, HeadVars),
	list__length(ExtraHeadVars, NumExtraVars),
	list__duplicate(NumExtraVars, (ground -> ground), ExtraModes),
	list__append(ExtraModes, ArgModes0, ArgModes),

	pred_info_name(PredInfo0, PredName),
	( PredName = "call" ->
		VarTypes = VarTypes1,
		VarSet = VarSet1,
		TypeVarSet = TypeVarSet0,
		Goal = Goal0
	;
		% process any polymorphic calls inside the goal
		map__from_corresponding_lists(HeadTypeVars, ExtraHeadVars,
					TypeInfoMap),
		Info0 = poly_info(VarSet1, VarTypes1, TypeVarSet0,
					TypeInfoMap, ModuleInfo),
		polymorphism__process_goal(Goal0, Goal1, Info0, Info),
		Info = poly_info(VarSet, VarTypes, TypeVarSet, _, _),
		% if we introduced any new head variables, we need to
		% fix up the quantification (non-local variables)
		( ExtraHeadVars = [] ->
			Goal = Goal1
		;
			implicitly_quantify_clause_body(HeadVars, Goal1, Goal)
		)
	),

	% set the new values of the fields in proc_info and pred_info
	proc_info_set_headvars(ProcInfo0, HeadVars, ProcInfo1),
	proc_info_set_goal(ProcInfo1, Goal, ProcInfo2),
	proc_info_set_varset(ProcInfo2, VarSet, ProcInfo3),
	proc_info_set_vartypes(ProcInfo3, VarTypes, ProcInfo4),
	proc_info_set_argmodes(ProcInfo4, ArgModes, ProcInfo),
	pred_info_set_typevarset(PredInfo0, TypeVarSet, PredInfo).
	
:- pred polymorphism__process_goal(hlds__goal, hlds__goal,
					poly_info, poly_info).
:- mode polymorphism__process_goal(in, out, in, out) is det.

polymorphism__process_goal(Goal0 - GoalInfo0, Goal) -->
	polymorphism__process_goal_2(Goal0, GoalInfo0, Goal).
	
:- pred polymorphism__process_goal_2(hlds__goal_expr, hlds__goal_info,
					hlds__goal, poly_info, poly_info).
:- mode polymorphism__process_goal_2(in, in, out, in, out) is det.

polymorphism__process_goal_2(
		call(PredId, ProcId, ArgVars0, Builtin, Context, Name, Follow),
		GoalInfo, Goal) -->
	polymorphism__process_call(PredId, ProcId, ArgVars0, 
			ArgVars, ExtraVars, ExtraGoals),
	{ goal_info_get_nonlocals(GoalInfo, NonLocals0) },
	{ set__insert_list(NonLocals0, ExtraVars, NonLocals) },
	{ goal_info_set_nonlocals(GoalInfo, NonLocals, CallGoalInfo) },
	{ Call = call(PredId, ProcId, ArgVars, Builtin, Context, Name, Follow)
			- CallGoalInfo },
	{ list__append(ExtraGoals, [Call], GoalList) },
	{ conj_list_to_goal(GoalList, GoalInfo, Goal) }.

polymorphism__process_goal_2(unify(XVar, Y, Mode, Unification, Context),
				GoalInfo, Goal) -->
	(
		{ Unification = complicated_unify(UniMode, _Category, Follow) },
		{ Y = var(YVar) }
	->
		=(poly_info(_, VarTypes, _, TypeInfoMap, ModuleInfo)),
		{ map__lookup(VarTypes, XVar, Type) },
		( { Type = term__variable(TypeVar) } ->
			% Convert polymorphic unifications into calls to
			% `unify/2', the general unification predicate, passing
			% the appropriate Type_info
			% 	=(TypeInfoVar, X, Y)
			% where TypeInfoVar is the type_info variable
			% associated with the type of the variables that
			% are being unified.

			{ module_info_get_predicate_table(ModuleInfo,
				PredicateTable) },
			{ predicate_table_search_name_arity(PredicateTable,
				"unify", 2, [CallPredId]) ->
				PredId = CallPredId
			;
				error("polymorphism.m: can't find `unify/2'")
			},
			% XXX Bug! - we should check that the mode is (in, in),
			%     and report an error (e.g. "unification of
			%     polymorphicly typed variables in partially
			%     instantiated mode") if it isn't
			{ ProcId = 0 },
			{ map__lookup(TypeInfoMap, TypeVar, TypeInfoVar) },
			{ SymName = unqualified("unify") },
			{ ArgVars = [TypeInfoVar, XVar, YVar] },
			{ code_util__is_builtin(ModuleInfo, PredId, ProcId,
				IsBuiltin) },
			{ CallContext = call_unify_context(XVar, Y, Context) },
			{ Goal = call(PredId, ProcId, ArgVars, IsBuiltin,
				yes(CallContext), SymName, Follow) - GoalInfo }

		; { type_to_type_id(Type, TypeId, _) } ->

			% Convert other complicated unifications into
			% calls to specific unification predicates, and then
			% recursively call polymorphism__process_goal_2
			% to insert extra arguments if necessary.

			{ module_info_get_special_pred_map(ModuleInfo,
				SpecialPredMap) },
			{ map__lookup(SpecialPredMap, unify - TypeId, PredId) },

			{ unify_proc__lookup_mode_num(ModuleInfo, TypeId,
				UniMode, ProcId) },
			{ SymName = unqualified("__Unify__") },
			{ ArgVars = [XVar, YVar] },
			{ is_builtin__make_builtin(no, no, IsBuiltin) },
			{ CallContext = call_unify_context(XVar, Y, Context) },
			{ Call = call(PredId, ProcId, ArgVars, IsBuiltin,
				yes(CallContext), SymName, Follow) },
			polymorphism__process_goal_2(Call, GoalInfo, Goal)
		;
			{ error("polymorphism: type_to_type_id failed") }
		)
	;
		% ordinary unifications are left unchanged
		{ Goal = unify(XVar, Y, Mode, Unification, Context) - GoalInfo }
	).

	% the rest of the clauses just process goals recursively

polymorphism__process_goal_2(conj(Goals0), GoalInfo, conj(Goals) - GoalInfo) -->
	polymorphism__process_goal_list(Goals0, Goals).
polymorphism__process_goal_2(disj(Goals0), GoalInfo, disj(Goals) - GoalInfo) -->
	polymorphism__process_goal_list(Goals0, Goals).
polymorphism__process_goal_2(not(Goal0), GoalInfo, not(Goal) - GoalInfo) -->
	polymorphism__process_goal(Goal0, Goal).
polymorphism__process_goal_2(switch(_, _, _), _, _) -->
	{ error("polymorphism__process_goal_2: switch unexpected") }.
polymorphism__process_goal_2(some(Vars, Goal0), GoalInfo,
			some(Vars, Goal) - GoalInfo) -->
	polymorphism__process_goal(Goal0, Goal).
polymorphism__process_goal_2(if_then_else(Vars, A0, B0, C0), GoalInfo,
			if_then_else(Vars, A, B, C) - GoalInfo) -->
	polymorphism__process_goal(A0, A),
	polymorphism__process_goal(B0, B),
	polymorphism__process_goal(C0, C).

:- pred polymorphism__process_goal_list(list(hlds__goal), list(hlds__goal),
					poly_info, poly_info).
:- mode polymorphism__process_goal_list(in, out, in, out) is det.

polymorphism__process_goal_list([], []) --> [].
polymorphism__process_goal_list([Goal0 | Goals0], [Goal | Goals]) -->
	polymorphism__process_goal(Goal0, Goal),
	polymorphism__process_goal_list(Goals0, Goals).

:- pred polymorphism__process_call(pred_id, proc_id, list(var), list(var),
					list(var), list(hlds__goal),
					poly_info, poly_info).
:- mode polymorphism__process_call(in, in, in, out, out, out, in, out) is det.

polymorphism__process_call(PredId, _ProcId, ArgVars0, ArgVars,
				ExtraVars, ExtraGoals, Info0, Info) :-
	Info0 = poly_info(VarSet0, VarTypes0, TypeVarSet0,
				TypeInfoMap, ModuleInfo),
	module_info_pred_info(ModuleInfo, PredId, PredInfo),
	pred_info_arg_types(PredInfo, PredTypeVarSet, PredArgTypes0),
		% rename apart
		% (this merge might be a performance bottleneck?)
	varset__merge(TypeVarSet0, PredTypeVarSet, PredArgTypes0,
			TypeVarSet, PredArgTypes),
	term__vars_list(PredArgTypes, PredTypeVars0),
	( PredTypeVars0 = [] ->
		% optimize for common case of non-polymorphic call
		ArgVars = ArgVars0,
		ExtraGoals = [],
		ExtraVars = [],
		Info = Info0
	;
		list__remove_dups(PredTypeVars0, PredTypeVars), % eliminate duplicates
		map__apply_to_list(ArgVars0, VarTypes0, ActualArgTypes),
		map__keys(TypeInfoMap, HeadTypeVars),
		map__init(TypeSubst0),
		( type_unify_list(ActualArgTypes, PredArgTypes, HeadTypeVars,
				TypeSubst0, TypeSubst1) ->
			TypeSubst = TypeSubst1
		;
		error("polymorphism__process_goal_2: type unification failed")
		),
		term__var_list_to_term_list(PredTypeVars, PredTypes0),
		term__apply_rec_substitution_to_list(PredTypes0, TypeSubst,
			PredTypes),
		polymorphism__make_vars(PredTypes, ModuleInfo, TypeInfoMap,
				VarSet0, VarTypes0,
				ExtraVars, ExtraGoals, VarSet, VarTypes),
		list__append(ExtraVars, ArgVars0, ArgVars),
		Info = poly_info(VarSet, VarTypes, TypeVarSet,
				TypeInfoMap, ModuleInfo)
	).

%---------------------------------------------------------------------------%

% Given a list of types, create a list of variables to hold the type_info
% for those types, and create a list of goals to initialize those type_info
% variables to the appropriate type_info structures for the types.
% Update the varset and vartypes accordingly.

:- pred polymorphism__make_vars(list(type), module_info,
				map(tvar, var), varset, map(var, type),
				list(var), list(hlds__goal),
				varset, map(var, type)).
:- mode polymorphism__make_vars(in, in, in, in, in, out, out, out, out) is det.

polymorphism__make_vars([], _, _, VarSet, VarTypes, [], [], VarSet, VarTypes).
polymorphism__make_vars([Type|Types], ModuleInfo, TypeInfoMap,
				VarSet0, VarTypes0,
				ExtraVars, ExtraGoals, VarSet, VarTypes) :-
	(
		type_to_type_id(Type, _TypeId, TypeArgs)
	->
		% This occurs for code where a predicate calls a polymorphic
		% predicate with a known value of the type variable.
		% For example, given
		%
		%	:- pred p(T1).
		%	:- pred q(T2).
		%	:- pred r(T3).
		%	p(X) :- q([X]), r(0).
		%
		% we know that in the call to q/1, T2 is bound to `list(T1)',
		% and in the call to r/1, T3 is bound to `int', and so
		% we translate it into
		%	:- pred p(T1, pred(T1, T1)).
		%	:- pred q(T2, pred(T2, T2)).
		%	:- pred r(T3, pred(T3, T3)).
		%	p(TypeInfo, X) :-
		%		q(	
		%			type_info(1,
		%				'__Unify__'<list/1>,
		%				'__Index__'<list/1>,
		%				'__Compare__'<list/1>,
		%				TypeInfo
		%			),
		%			[X]
		%		),
		%		r(	
		%			type_info(0,
		%				builtin_unify_int,
		%				builtin_index_int,
		%				builtin_compare_int
		%			),
		%			0
		%		).


		% Create a unification `CountVar = <NumTypeArgs>'
		varset__new_var(VarSet0, CountVar, VarSet1a),
		varset__name_var(VarSet1a, CountVar, "TypeArity", VarSet1),
		term__context_init(Context),
		IntType = term__functor(term__atom("int"), [], Context),
		map__set(VarTypes0, CountVar, IntType, VarTypes1),
		list__length(TypeArgs, NumTypeArgs),
		polymorphism__init_with_int_constant(CountVar, NumTypeArgs,
			CountGoal),

		% Create the unifications to initialize the special pred
		% variables for this type:
		%	SpecialPred1 = __Unify__<type>,
		%	SpecialPred2 = __Index__<type>,
		%	SpecialPred3 = __Compare__<type>.

		special_pred_list(SpecialPreds),
		polymorphism__get_special_proc_list(SpecialPreds, Type,
			ModuleInfo, VarSet1, VarTypes1,
			SpecialPredVars, SpecialPredGoals, VarSet2, VarTypes2),

		% Create the unifications to recursively initialize the
		% type_info for any argument types of a polymorphic type

                polymorphism__make_vars(TypeArgs, ModuleInfo, TypeInfoMap,
			VarSet2, VarTypes2,
			TypeInfoVars, TypeInfoGoals, VarSet3, VarTypes3),

		% Create a unification for the type_info variable for
		% this type:
		%	TypeInfoVar = type_info(CountVar,
		%				SpecialPredVars...,
		%				TypeInfoVars...).

		list__append([CountVar | SpecialPredVars], TypeInfoVars,
			ArgVars),
		polymorphism__init_type_info_var(Type, ArgVars,
			VarSet3, VarTypes3,
			Var, TypeInfoGoal, VarSet4, VarTypes4),

		list__append([CountGoal | SpecialPredGoals], TypeInfoGoals,
			ExtraGoals0),
		list__append(ExtraGoals0, [TypeInfoGoal], ExtraGoals1)
	;
		Type = term__variable(TypeVar1),
		map__search(TypeInfoMap, TypeVar1, TypeInfoVar)
	->
		% This occurs for code where a predicate calls a polymorphic
		% predicate with a bound but unknown value of the type variable.
		% For example, in
		%
		%	:- pred p(T1).
		%	:- pred q(T2).
		%	p(X) :- q(X).
		%
		% we know that `T2' is bound to `T1', and we translate it into
		%
		%	:- pred p(T1, pred(T1, T1)).
		%	:- pred q(T2, pred(T2, T2)).
		%	p(TypeInfo, X) :- q(TypeInfo, X).
		
		Var = TypeInfoVar,
		ExtraGoals1 = [],
		VarSet4 = VarSet0,
		VarTypes4 = VarTypes0
	;
		% This occurs for code where a predicate calls a polymorphic
		% predicate with an unbound type variable, for example
		%
		%	:- pred p.
		%	:- pred q(list(T)).
		%	p :- q([]).
		%
		% In this case T is unbound, so there cannot be any objects
		% of type T, and so q/1 cannot possibly use the unification
		% predicate for type T.  We just pass a dummy value (0).
		%
		%	:- pred p.
		%	:- pred q(T, pred(T, T)).
		%	p :- q(0, []).
		%
		% (This isn't really type-correct, but we're already past
		% the type-checker.  Passing 0 should ensure that we get
		% a core dump if we ever attempt to call the unify pred.)
		%
		% XXX what about io__read_anything/3?
		% e.g.
		%	foo --> io__read_anything(_).
		% ?

		% introduce a new variable, and 
		% create a construction unification which initializes the
		% variable to zero
		polymorphism__new_type_info_var(Type, VarSet0, VarTypes0,
					Var, VarSet4, VarTypes4),
		polymorphism__init_with_int_constant(Var, 0, Goal),
		ExtraGoals1 = [Goal]
	),
	ExtraVars = [Var | ExtraVars1],
	list__append(ExtraGoals1, ExtraGoals2, ExtraGoals),
	polymorphism__make_vars(Types, ModuleInfo, TypeInfoMap,
				VarSet4, VarTypes4,
				ExtraVars1, ExtraGoals2, VarSet, VarTypes).

	% Create a construction unification `Var = <Num>'
	% where Var is a freshly introduced variable and Num is an
	% integer constant.

:- pred polymorphism__init_with_int_constant(var, int, hlds__goal).
:- mode polymorphism__init_with_int_constant(in, in, out) is det.

polymorphism__init_with_int_constant(CountVar, Num, CountUnifyGoal) :-

	CountConsId = int_const(Num),
	CountUnification = construct(CountVar, CountConsId, [], []),

	CountConst = term__integer(Num),
	CountTerm = functor(CountConst, []),
	CountInst = bound([functor(CountConst, [])]),
	CountUnifyMode = (free -> CountInst) - (CountInst -> CountInst),
	CountUnifyContext = unify_context(explicit, []),
		% XXX the UnifyContext is wrong
	CountUnify = unify(CountVar, CountTerm, CountUnifyMode,
		CountUnification, CountUnifyContext),

	% create a goal_info for the unification

	goal_info_init(CountGoalInfo0),
	set__singleton_set(CountNonLocals, CountVar),
	goal_info_set_nonlocals(CountGoalInfo0, CountNonLocals,	
				CountGoalInfo1),
	map__init(CountInstMapping0),
	map__set(CountInstMapping0, CountVar, CountInst,
		CountInstMapping),
	goal_info_set_instmap_delta(CountGoalInfo1,
		reachable(CountInstMapping), CountGoalInfo),

	CountUnifyGoal = CountUnify - CountGoalInfo.

:- pred polymorphism__get_special_proc_list(list(special_pred_id),
			type, module_info, varset, map(var, type),
			list(var), list(hlds__goal), varset, map(var, type)).
:- mode polymorphism__get_special_proc_list(in, in, in, in, in,
					out, out, out, out) is det.

polymorphism__get_special_proc_list([],
		_Type, _ModuleInfo, VarSet, VarTypes,
		[], [], VarSet, VarTypes).
polymorphism__get_special_proc_list([Id | Ids],
		Type, ModuleInfo, VarSet0, VarTypes0,
		[Var | Vars], [Goal | Goals], VarSet, VarTypes) :-

	% introduce a fresh variable of the appropriate higher-order pred type

	special_pred_info(Id, Type, PredName, TypeArgs, _Modes, _Det),
	varset__new_var(VarSet0, Var, VarSet1a),
	string__append("Var__", PredName, VarName),
	varset__name_var(VarSet1a, Var, VarName, VarSet1),
	term__context_init(Context),
	PredType = term__functor(term__atom("pred"), TypeArgs, Context),
	map__set(VarTypes0, Var, PredType, VarTypes1),

	% get the ConsId for the address of the appropriate pred
	% for the operation specified by Id applied to Type.

	classify_type(Type, ModuleInfo, TypeCategory),
	polymorphism__get_special_proc(TypeCategory, Id, ModuleInfo, ConsId),

	% create a construction unification which unifies the fresh
	% variable with the address constant obtained above

	Unification = construct(Var, ConsId, [], []),

	Functor = term__atom(PredName),
	Term = functor(Functor, []),

	Inst = bound([functor(Functor, [])]),
	UnifyMode = (free -> Inst) - (Inst -> Inst),
	UnifyContext = unify_context(explicit, []),
		% XXX the UnifyContext is wrong
	Unify = unify(Var, Term, UnifyMode, Unification, UnifyContext),

	% create a goal_info for the unification

	goal_info_init(GoalInfo0),
	set__singleton_set(NonLocals, Var),
	goal_info_set_nonlocals(GoalInfo0, NonLocals,	GoalInfo1),
	map__init(InstMapping0),
	map__set(InstMapping0, Var, Inst, InstMapping),
	goal_info_set_instmap_delta(GoalInfo1, reachable(InstMapping),
		GoalInfo),
	Goal = Unify - GoalInfo,

	polymorphism__get_special_proc_list(Ids,
		Type, ModuleInfo, VarSet1, VarTypes1,
		Vars, Goals, VarSet, VarTypes).

:- pred polymorphism__get_special_proc(builtin_type, special_pred_id,
					module_info, cons_id).
:- mode polymorphism__get_special_proc(in, in, in, out) is det.

polymorphism__get_special_proc(TypeCategory, SpecialPredId, ModuleInfo,
		ConsId) :-
	( TypeCategory = user_type(Type) ->
		module_info_get_special_pred_map(ModuleInfo, SpecialPredMap),
		( type_to_type_id(Type, TypeId, _TypeArgs) ->
			map__lookup(SpecialPredMap, SpecialPredId - TypeId,
				PredId)
		;
			error(
		"polymorphism__get_special_proc: type_to_type_id failed")
		)
	;
		polymorphism__get_category_name(TypeCategory, CategoryName),
		special_pred_name_arity(SpecialPredId, SpecialName, Arity),
		string__append_list(
			["builtin_", SpecialName, "_", CategoryName], PredName),
		polymorphism__get_pred_id(PredName, Arity, ModuleInfo, PredId)
	),
	ProcId = 0,	% always use the first mode of a special predicate
	ConsId = address_const(PredId, ProcId).

:- pred polymorphism__get_category_name(builtin_type, string).
:- mode polymorphism__get_category_name(in, out) is det.

polymorphism__get_category_name(int_type, "int").
polymorphism__get_category_name(char_type, "int").
polymorphism__get_category_name(enum_type, "int").
polymorphism__get_category_name(float_type, "float").
polymorphism__get_category_name(str_type, "string").
polymorphism__get_category_name(pred_type, "pred").
polymorphism__get_category_name(polymorphic_type, _) :-
	error("polymorphism__get_category_name: polymorphic type").
polymorphism__get_category_name(user_type(_), _) :-
	error("polymorphism__get_category_name: user_type").

	% find the unification procedure with the specified name

:- pred polymorphism__get_pred_id(string, int, module_info, pred_id).
:- mode polymorphism__get_pred_id(in, in, in, out) is det.

polymorphism__get_pred_id(Name, Arity, ModuleInfo, PredId) :-
	module_info_get_predicate_table(ModuleInfo, PredicateTable),
	(
		predicate_table_search_name_arity(PredicateTable, Name, Arity,
			[PredId1])
	->
		PredId = PredId1
	;
		error("polymorphism__get_pred_id: pred_id lookup failed")
	).


	% Create a unification for the type_info variable for
	% this type:
	%	TypeInfoVar = type_info(CountVar,
	%				SpecialPredVars...,
	%				TypeInfoVars...).

:- pred polymorphism__init_type_info_var(
		type, list(var), varset, map(var, type),
		var, hlds__goal, varset, map(var, type)).
:- mode polymorphism__init_type_info_var(in, in, in, in, out, out, out, out)
	is det.

polymorphism__init_type_info_var(Type, ArgVars, VarSet0, VarTypes0,
			TypeInfoVar, TypeInfoGoal, VarSet, VarTypes) :-

	TypeInfoFunctor = term__atom("type_info"),
	ConsId = cons("type_info", 1),
	TypeInfoTerm = functor(TypeInfoFunctor, ArgVars),

	% introduce a new variable
	polymorphism__new_type_info_var(Type, VarSet0, VarTypes0,
		TypeInfoVar, VarSet, VarTypes),

	% create the construction unification to initialize it
	UniMode = (free - ground -> ground - ground),
	list__length(ArgVars, NumArgVars),
	list__duplicate(NumArgVars, UniMode, UniModes),
	Unification = construct(TypeInfoVar, ConsId, ArgVars, UniModes),
	UnifyMode = (free -> ground) - (ground -> ground),
	UnifyContext = unify_context(explicit, []),
		% XXX the UnifyContext is wrong
	Unify = unify(TypeInfoVar, TypeInfoTerm, UnifyMode,
			Unification, UnifyContext),

	% create a goal_info for the unification
	goal_info_init(GoalInfo0),
	set__list_to_set([TypeInfoVar | ArgVars], NonLocals),
	goal_info_set_nonlocals(GoalInfo0, NonLocals, GoalInfo1),
	map__init(InstMapping0),
	list__duplicate(NumArgVars, ground, ArgInsts),
		% note that we could perhaps be more accurate than
		% `ground', but hopefully it shouldn't make any
		% difference.
	map__set(InstMapping0, TypeInfoVar,
		bound([functor(TypeInfoFunctor, ArgInsts)]),
		InstMapping),
	goal_info_set_instmap_delta(GoalInfo1, reachable(InstMapping),
		GoalInfo),

	TypeInfoGoal = Unify - GoalInfo.

:- pred polymorphism__make_head_vars(list(tvar), tvarset,
				varset, map(var, type),
				list(var), varset, map(var, type)).
:- mode polymorphism__make_head_vars(in, in, in, in, out, out, out) is det.

polymorphism__make_head_vars([], _, VarSet, VarTypes, [], VarSet, VarTypes).
polymorphism__make_head_vars([TypeVar|TypeVars], TypeVarSet,
				VarSet0, VarTypes0,
				TypeInfoVars, VarSet, VarTypes) :-
	Type = term__variable(TypeVar),
	polymorphism__new_type_info_var(Type, VarSet0, VarTypes0,
					Var, VarSet1, VarTypes1),
	( varset__lookup_name(TypeVarSet, TypeVar, TypeVarName) ->
		string__append("TypeInfo_for_", TypeVarName, VarName),
		varset__name_var(VarSet1, Var, VarName, VarSet2)
	;
		VarSet2 = VarSet1
	),
	TypeInfoVars = [Var | TypeInfoVars1],
	polymorphism__make_head_vars(TypeVars, TypeVarSet,
				VarSet2, VarTypes1,
				TypeInfoVars1, VarSet, VarTypes).

:- pred polymorphism__new_type_info_var(type, varset, map(var, type),
					var, varset, map(var, type)).
:- mode polymorphism__new_type_info_var(in, in, in, out, out, out) is det.

polymorphism__new_type_info_var(Type, VarSet0, VarTypes0,
				Var, VarSet, VarTypes) :-
	% introduce new variable
	varset__new_var(VarSet0, Var, VarSet1),
	varset__name_var(VarSet1, Var, "TypeInfo", VarSet),
	term__context_init(Context),
	UnifyPredType = term__functor(term__atom("type_info"), [Type],
				Context),
	map__set(VarTypes0, Var, UnifyPredType, VarTypes).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
