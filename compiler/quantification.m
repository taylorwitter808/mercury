%-----------------------------------------------------------------------------%
% Copyright (C) 1994-2005 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% File: quantification.m.
% Main authors: fjh, conway.

% Make implicit quantification explicit, and rename apart variables
% with the same name that appear in distinct scopes. For the rules on
% implicit quantification, see the Mercury language reference manual.
%
% This pass also expands out bi-implications (that has to be done after
% quantification, and preferably as soon as possible, so we do it here).
%
% Rather than making implicit quantification explicit by inserting additional
% existential quantifiers in the form of `some/2' goals, we instead record
% existential quantification in the goal_info for each goal. In fact we could
% (and maybe even should?) even delete any explicit existential quantifiers
% that were present in the source code, since the information they convey
% will be stored in the goal_info (we currently don't do that).
%
% The important piece of information that later stages of the compiler
% want to know is "Does this goal bind any of its non-local variables?".
% So, rather than storing a list of the variables which _are_ existentially
% quantified in the goal_info, we store the set of variables which are _not_
% quantified.

%-----------------------------------------------------------------------------%

:- module hlds__quantification.

:- interface.

:- import_module hlds__hlds_goal.
:- import_module hlds__hlds_pred.
:- import_module parse_tree__prog_data.

:- import_module list.
:- import_module set.

	%
	% When the compiler performs structure reuse, using
	% the ordinary non-locals during code generation
	% causes variables taken from the reused cell in
	% a reconstruction to be extracted and possibly stored
	% on the stack unnecessarily.
	%
	% For the example below, the variables `B' ... `H' are
	% extracted from the term and stored on the stack across
	% the call.
	%
	% To avoid this, the compiler computes a set of `code-gen non-locals'
	% which are the same as the ordinary non-locals, except that the
	% variables taken from the reused cell are considered to be local
	% to the goal. No renaming is performed when computing
	% the code-gen non-locals to avoid stuffing up the ordinary
	% non-locals.
	%
	% Mode information is always computed using the ordinary non-locals.
	%
	% :- pred update(X::in, foo::di, foo::uo) is det.
	% update(A0, Foo0, Foo) :-
	% 	Foo0 = foo(_, B, C, D, E, F, G, H),
	%	some_call(A0, A),
	% 	Foo0 = foo(A, B, C, D, E, F, G, H).
	%
:- type nonlocals_to_recompute
	--->	ordinary_nonlocals
	;	code_gen_nonlocals.

:- pred implicitly_quantify_clause_body(nonlocals_to_recompute::in,
	list(prog_var)::in, list(quant_warning)::out,
	hlds_goal::in, hlds_goal::out, prog_varset::in, prog_varset::out,
	vartypes::in, vartypes::out) is det.

	% As above, with `ordinary_nonlocals' passed as the first argument.
:- pred implicitly_quantify_clause_body(list(prog_var)::in,
	list(quant_warning)::out, hlds_goal::in, hlds_goal::out,
	prog_varset::in, prog_varset::out, vartypes::in, vartypes::out) is det.

:- pred implicitly_quantify_goal(nonlocals_to_recompute::in,
	set(prog_var)::in, list(quant_warning)::out,
	hlds_goal::in, hlds_goal::out, prog_varset::in, prog_varset::out,
	vartypes::in, vartypes::out) is det.

	% As above, with `ordinary_nonlocals' passed as the first argument.
:- pred implicitly_quantify_goal(set(prog_var)::in, list(quant_warning)::out,
	hlds_goal::in, hlds_goal::out, prog_varset::in, prog_varset::out,
	vartypes::in, vartypes::out) is det.

:- pred requantify_proc(nonlocals_to_recompute::in,
	proc_info::in, proc_info::out) is det.

	% As above, with `ordinary_nonlocals' passed as the first argument.
:- pred requantify_proc(proc_info::in, proc_info::out) is det.

	% We return a list of warnings back to make_hlds.m.
	% Currently the only thing we warn about is variables with
	% overlapping scopes.

:- type quant_warning
	--->	warn_overlap(list(prog_var), prog_context).

	% quantification__goal_vars(Goal, Vars):
	%	Vars is the set of variables that are free (unquantified)
	%	in Goal.
:- pred quantification__goal_vars(nonlocals_to_recompute::in,
	hlds_goal::in, set(prog_var)::out) is det.

	% As above, with `ordinary_nonlocals' passed as the first argument.
:- pred quantification__goal_vars(hlds_goal::in, set(prog_var)::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module hlds__goal_util.
:- import_module hlds__instmap.

:- import_module bool.
:- import_module enum.
:- import_module map.
:- import_module require.
:- import_module sparse_bitset.
:- import_module std_util.
:- import_module term.
:- import_module varset.

	% The `outside vars', `lambda outside vars', and `quant vars'
	% fields are inputs; the `nonlocals' field is output; and
	% the `seen so far', the varset, the types, and the warnings fields
	% are threaded (i.e. both input and output).
	% We use the convention that the input fields are callee save,
	% and the outputs are caller save.
	% The nonlocals_to_recompute field is constant.
:- type quant_info
	--->	quant_info(
			nonlocals_to_recompute	:: nonlocals_to_recompute,
			outside			:: set_of_var,
			quant_vars		:: set_of_var,
			lambda_outside		:: set_of_var,
			nonlocals		:: set_of_var,
			seen			:: set_of_var,
			varset			:: prog_varset,
			vartypes		:: vartypes,
			warnings		:: list(quant_warning)
		).

	% Until we have user-specified pretty printing in the
	% debugger, debugging will be much easier if set_of_var
	% is just `set(prog_var)'.
	% None of the calls to the predicates and functions operating
	% on sets in this module are module qualified so we can switch
	% representation just by changing this line.
%:- type set_of_var == set(prog_var).
:- type set_of_var == sparse_bitset(prog_var).

	% `OutsideVars' are the variables that have occurred free outside
	% this goal, not counting occurrences in parallel goals and not
	% counting occurrences in lambda goals, or which have been explicitly
	% existentially quantified over a scope which includes the current
	% goal in a negated context.
	%
	% `QuantVars' are the variables not in `OutsideVars' that have been
	% explicitly existentially quantified over a scope which includes the
	% current goal in a positive (non-negated) context.
	%
	% `OutsideLambdaVars' are the variables that have occurred free in
	% a lambda expression outside this goal, not counting occurrences in
	% parallel goals (and if this goal is itself inside a lambda
	% expression, not counting occurrences outside that lambda expression).
	%
	% For example, for
	%
	%	test :- some [X] (p(X) ; not q(X) ; r(X), s(X)).
	%
	% when processing `r(X), s(X)', OutsideVars will be [] and
	% QuantifiedVars will be [X]; when processing `r(X)',
	% OutsideVars will be [X] and QuantifiedVars will be [],
	% since now [X] has occured in a goal (`s(X)') outside of `r(X)'.
	% When processing `not q(X)', OutsideVars will be [] and
	% QuantifiedVars will be [X]; when processing `q(X)',
	% OutsideVars will be [X] and QuantifiedVars will be [],
	% since the quantification can't be pushed inside the negation.

%-----------------------------------------------------------------------------%

implicitly_quantify_clause_body(HeadVars, Warnings,
		!Goal, !Varset, !VarTypes) :-
	implicitly_quantify_clause_body(ordinary_nonlocals, HeadVars, Warnings,
		!Goal, !Varset, !VarTypes).

implicitly_quantify_clause_body(RecomputeNonLocals, HeadVars, Warnings,
		!Goal, !Varset, !VarTypes) :-
	list_to_set(HeadVars, OutsideVars),
	implicitly_quantify_goal(RecomputeNonLocals, OutsideVars, Warnings,
		!Goal, !Varset, !VarTypes).

requantify_proc(ProcInfo0, ProcInfo) :-
	requantify_proc(ordinary_nonlocals, ProcInfo0, ProcInfo).

requantify_proc(RecomputeNonLocals, !ProcInfo) :-
	proc_info_headvars(!.ProcInfo, HeadVars),
	proc_info_varset(!.ProcInfo, Varset0),
	proc_info_vartypes(!.ProcInfo, VarTypes0),
	proc_info_goal(!.ProcInfo, Goal0),
	implicitly_quantify_clause_body(RecomputeNonLocals, HeadVars, _,
		Goal0, Goal, Varset0, Varset, VarTypes0, VarTypes),
	proc_info_set_varset(Varset, !ProcInfo),
	proc_info_set_vartypes(VarTypes, !ProcInfo),
	proc_info_set_goal(Goal, !ProcInfo).

implicitly_quantify_goal(OutsideVars, Warnings, !Goal, !Varset, !VarTypes) :-
	implicitly_quantify_goal(ordinary_nonlocals, OutsideVars, Warnings,
		!Goal, !Varset, !VarTypes).

implicitly_quantify_goal(RecomputeNonLocals, OutsideVars, Warnings,
		!Goal, !Varset, !VarTypes) :-
	implicitly_quantify_goal_2(ordinary_nonlocals, OutsideVars, Warnings,
		!Goal, !Varset, !VarTypes),
	(
		RecomputeNonLocals = code_gen_nonlocals,

		% If the goal does not contain a reconstruction,
		% the code-gen nonlocals and the ordinary non-locals
		% are the same.
		goal_contains_reconstruction(!.Goal)
	->
		implicitly_quantify_goal_2(code_gen_nonlocals, OutsideVars, _,
			!Goal, !Varset, !VarTypes)
	;
		true
	).

:- pred implicitly_quantify_goal_2(nonlocals_to_recompute::in,
	set(prog_var)::in, list(quant_warning)::out,
	hlds_goal::in, hlds_goal::out, prog_varset::in, prog_varset::out,
	vartypes::in, vartypes::out) is det.

implicitly_quantify_goal_2(RecomputeNonLocals, OutsideVars0, Warnings,
		!Goal, !Varset, !VarTypes) :-
	OutsideVars = set_to_bitset(OutsideVars0),
	quantification__init(RecomputeNonLocals, OutsideVars,
		!.Varset, !.VarTypes, QuantInfo0),
	implicitly_quantify_goal(!Goal, QuantInfo0, QuantInfo),
	quantification__get_varset(!:Varset, QuantInfo, _),
	quantification__get_vartypes(!:VarTypes, QuantInfo, _),
	quantification__get_warnings(Warnings0, QuantInfo, _),
	list__reverse(Warnings0, Warnings).

:- pred implicitly_quantify_goal(hlds_goal::in, hlds_goal::out,
	quant_info::in, quant_info::out) is det.

implicitly_quantify_goal(Goal0 - GoalInfo0, Goal - GoalInfo, !Info) :-
	quantification__get_seen(SeenVars, !Info),
	goal_info_get_context(GoalInfo0, Context),
	implicitly_quantify_goal_2(Goal0, Goal1, Context, !Info),
	quantification__get_nonlocals(NonLocalVars, !Info),
	quantification__get_nonlocals_to_recompute(NonLocalsToRecompute,
		!Info),
	(
		% If there are any variables that are local to the goal
		% which we have come across before, then we rename them
		% apart.
		quantification__goal_vars_bitset(NonLocalsToRecompute,
			Goal0 - GoalInfo0, GoalVars0),
		difference(GoalVars0, NonLocalVars, LocalVars),
		intersect(SeenVars, LocalVars, RenameVars),
		\+ empty(RenameVars)
	->
		quantification__rename_apart(RenameVars, _, Goal1 - GoalInfo0,
			Goal - GoalInfo1, !Info)
	;
		Goal = Goal1,
		GoalInfo1 = GoalInfo0
	),
	quantification__set_goal_nonlocals(NonLocalVars, NonLocalVarsSet,
		GoalInfo1, GoalInfo2, !Info),
	%
	% If the non-locals set has shrunk (e.g. because some optimization
	% optimizes away the other occurrences of a variable, causing it
	% to become local when previously it was non-local),
	% then we may need to likewise shrink the instmap delta.
	%
	goal_info_get_instmap_delta(GoalInfo2, InstMapDelta0),
	instmap_delta_restrict(InstMapDelta0, NonLocalVarsSet, InstMapDelta),
	goal_info_set_instmap_delta(GoalInfo2, InstMapDelta, GoalInfo).

:- pred implicitly_quantify_goal_2(hlds_goal_expr::in, hlds_goal_expr::out,
	prog_context::in, quant_info::in, quant_info::out) is det.

	% After this pass, explicit quantifiers are redundant,
	% since all variables which were explicitly quantified
	% have been renamed apart.  So we don't keep them.
	% We need to keep the structure, though, so that mode
	% analysis doesn't try to reorder through quantifiers.
	% (Actually it would make sense to allow mode analysis
	% to do that, but the reference manual says it doesn't,
	% so we don't.)  Thus we replace `some(Vars, Goal0)' with
	% an empty quantifier `some([], Goal)'.

implicitly_quantify_goal_2(Expr0, Expr, Context, !Info) :-
	Expr0 = some(Vars0, CanRemove, Goal0),
	Expr = some([], CanRemove, Goal),
	quantification__get_outside(OutsideVars, !Info),
	quantification__get_lambda_outside(LambdaOutsideVars, !Info),
	quantification__get_quant_vars(QuantVars, !Info),
		% Rename apart all the quantified
		% variables that occur outside this goal.
	list_to_set(Vars0, QVars),
	intersect(OutsideVars, QVars, RenameVars1),
	intersect(LambdaOutsideVars, QVars, RenameVars2),
	union(RenameVars1, RenameVars2, RenameVars),
	( empty(RenameVars) ->
		Goal1 = Goal0,
		Vars = Vars0
	;
		quantification__warn_overlapping_scope(RenameVars, Context,
			!Info),
		quantification__rename_apart(RenameVars, RenameMap,
			Goal0, Goal1, !Info),
		goal_util__rename_var_list(Vars0, no, RenameMap, Vars)
	),
	quantification__update_seen_vars(QVars, !Info),
	insert_list(QuantVars, Vars, QuantVars1),
	quantification__set_quant_vars(QuantVars1, !Info),
	implicitly_quantify_goal(Goal1, Goal, !Info),
	quantification__get_nonlocals(NonLocals0, !Info),
	delete_list(NonLocals0, Vars, NonLocals),
	quantification__set_quant_vars(QuantVars, !Info),
	quantification__set_nonlocals(NonLocals, !Info).

implicitly_quantify_goal_2(Expr0, Expr, _, !Info) :-
	Expr0 = conj(Goals0),
	Expr = conj(Goals),
	implicitly_quantify_conj(Goals0, Goals, !Info).

implicitly_quantify_goal_2(Expr0, Expr, _, !Info) :-
	Expr0 = par_conj(Goals0),
	Expr = par_conj(Goals),
	implicitly_quantify_conj(Goals0, Goals, !Info).

implicitly_quantify_goal_2(Expr0, Expr, _, !Info) :-
	Expr0 = disj(Goals0),
	Expr = disj(Goals),
	implicitly_quantify_disj(Goals0, Goals, !Info).

implicitly_quantify_goal_2(Expr0, Expr, _, !Info) :-
	Expr0 = switch(Var, Det, Cases0),
	Expr = switch(Var, Det, Cases),
	implicitly_quantify_cases(Cases0, Cases, !Info),
		% The switch variable is guaranteed to be non-local to the
		% switch, since it has to be bound elsewhere, so we put it
		% in the nonlocals here.
	quantification__get_nonlocals(NonLocals0, !Info),
	insert(NonLocals0, Var, NonLocals),
	quantification__set_nonlocals(NonLocals, !Info).

implicitly_quantify_goal_2(Expr0, Expr, _, !Info) :-
	Expr0 = not(Goal0),
	Expr = not(Goal),
		% quantified variables cannot be pushed inside a negation,
		% so we insert the quantified vars into the outside vars set,
		% and initialize the new quantified vars set to be empty
		% (the lambda outside vars remain unchanged)
	quantification__get_quant_vars(QuantVars, !Info),
	quantification__get_outside(OutsideVars, !Info),
	union(OutsideVars, QuantVars, OutsideVars1),
	init(QuantVars1),
	quantification__set_quant_vars(QuantVars1, !Info),
	quantification__set_outside(OutsideVars1, !Info),
	implicitly_quantify_goal(Goal0, Goal, !Info),
	quantification__set_outside(OutsideVars, !Info),
	quantification__set_quant_vars(QuantVars, !Info).

	% After this pass, explicit quantifiers are redundant,
	% since all variables which were explicitly quantified
	% have been renamed apart.  So we don't keep them.
	% Thus we replace `if_then_else(Vars, ....)' with
	% `if_then_else([], ...)'.
implicitly_quantify_goal_2(Expr0, Expr, Context, !Info) :-
	Expr0 = if_then_else(Vars0, Cond0, Then0, Else0),
	Expr = if_then_else([], Cond, Then, Else),
	quantification__get_quant_vars(QuantVars, !Info),
	quantification__get_outside(OutsideVars, !Info),
	quantification__get_lambda_outside(LambdaOutsideVars, !Info),
	list_to_set(Vars0, QVars),
		% Rename apart those variables that
		% are quantified to the cond and then
		% of the i-t-e that occur outside the
		% i-t-e.
	intersect(OutsideVars, QVars, RenameVars1),
	intersect(LambdaOutsideVars, QVars, RenameVars2),
	union(RenameVars1, RenameVars2, RenameVars),
	( empty(RenameVars) ->
		Cond1 = Cond0,
		Then1 = Then0,
		Vars = Vars0
	;
		quantification__warn_overlapping_scope(RenameVars, Context,
			!Info),
		quantification__rename_apart(RenameVars, RenameMap,
			Cond0, Cond1, !Info),
		goal_util__rename_vars_in_goal(Then0, RenameMap, Then1),
		goal_util__rename_var_list(Vars0, no, RenameMap, Vars)
	),
	insert_list(QuantVars, Vars, QuantVars1),
	quantification__get_nonlocals_to_recompute(NonLocalsToRecompute,
		!Info),
	quantification__goal_vars(NonLocalsToRecompute,
		Then1, VarsThen, LambdaVarsThen),
	union(OutsideVars, VarsThen, OutsideVars1),
	union(LambdaOutsideVars, LambdaVarsThen, LambdaOutsideVars1),
	quantification__set_quant_vars(QuantVars1, !Info),
	quantification__set_outside(OutsideVars1, !Info),
	quantification__set_lambda_outside(LambdaOutsideVars1, !Info),
	quantification__update_seen_vars(QVars, !Info),
	implicitly_quantify_goal(Cond1, Cond, !Info),
	quantification__get_nonlocals(NonLocalsCond, !Info),
	union(OutsideVars, NonLocalsCond, OutsideVars2),
	quantification__set_outside(OutsideVars2, !Info),
	quantification__set_lambda_outside(LambdaOutsideVars, !Info),
	implicitly_quantify_goal(Then1, Then, !Info),
	quantification__get_nonlocals(NonLocalsThen, !Info),
	quantification__set_outside(OutsideVars, !Info),
	quantification__set_quant_vars(QuantVars, !Info),
	implicitly_quantify_goal(Else0, Else, !Info),
	quantification__get_nonlocals(NonLocalsElse, !Info),
	union(NonLocalsCond, NonLocalsThen, NonLocalsIfThen),
	union(NonLocalsIfThen, NonLocalsElse, NonLocalsIfThenElse),
	intersect(NonLocalsIfThenElse, OutsideVars, NonLocalsO),
	intersect(NonLocalsIfThenElse, LambdaOutsideVars, NonLocalsL),
	union(NonLocalsO, NonLocalsL, NonLocals),
	quantification__set_nonlocals(NonLocals, !Info).

implicitly_quantify_goal_2(Expr, Expr, _, !Info) :-
	Expr = call(_, _, HeadVars, _, _, _),
	implicitly_quantify_atomic_goal(HeadVars, !Info).

implicitly_quantify_goal_2(Expr, Expr, _, !Info) :-
	Expr = generic_call(GenericCall, CallArgVars, _, _),
	goal_util__generic_call_vars(GenericCall, ArgVars0),
	list__append(ArgVars0, CallArgVars, ArgVars),
	implicitly_quantify_atomic_goal(ArgVars, !Info).

implicitly_quantify_goal_2(Expr0, Expr, Context, !Info) :-
	Expr0 = unify(Var, UnifyRHS0, Mode, Unification0, UnifyContext),
	Expr = unify(Var, UnifyRHS, Mode, Unification, UnifyContext),
	quantification__get_outside(OutsideVars, !Info),
	quantification__get_lambda_outside(LambdaOutsideVars, !Info),
	TypeInfoVars = quantification__get_unify_typeinfos(Unification0),
	( Unification0 = construct(_, _, _, _, How, _, MaybeSize) ->
		( How = reuse_cell(cell_to_reuse(ReuseVar0, _, SetArgs)) ->
			MaybeSetArgs = yes(SetArgs),
			MaybeReuseVar = yes(ReuseVar0)
		;
			MaybeSetArgs = no,
			MaybeReuseVar = no
		),
		( MaybeSize = yes(dynamic_size(SizeVar0)) ->
			MaybeSizeVar = yes(SizeVar0)
		;
			MaybeSizeVar = no
		)
	;
		MaybeSetArgs = no,
		MaybeReuseVar = no,
		MaybeSizeVar = no
	),
	implicitly_quantify_unify_rhs(MaybeSetArgs, Context,
		UnifyRHS0, UnifyRHS, Unification0, Unification, !Info),
	quantification__get_nonlocals(VarsUnifyRHS, !Info),
	insert(VarsUnifyRHS, Var, GoalVars0),
	insert_list(GoalVars0, TypeInfoVars, GoalVars1),
	( MaybeReuseVar = yes(ReuseVar) ->
		insert(GoalVars1, ReuseVar, GoalVars2)
	;
		GoalVars2 = GoalVars1
	),
	( MaybeSizeVar = yes(SizeVar) ->
		insert(GoalVars2, SizeVar, GoalVars)
	;
		GoalVars = GoalVars2
	),
	quantification__update_seen_vars(GoalVars, !Info),
	intersect(GoalVars, OutsideVars, NonLocalVars1),
	intersect(GoalVars, LambdaOutsideVars, NonLocalVars2),
	union(NonLocalVars1, NonLocalVars2, NonLocalVars),
	quantification__set_nonlocals(NonLocalVars, !Info).

implicitly_quantify_goal_2(Expr, Expr, _, !Info) :-
	Expr = foreign_proc(_, _, _, Args, ExtraArgs, _),
	Vars = list__map(foreign_arg_var, Args),
	ExtraVars = list__map(foreign_arg_var, ExtraArgs),
	list__append(Vars, ExtraVars, AllVars),
	implicitly_quantify_atomic_goal(AllVars, !Info).

implicitly_quantify_goal_2(Expr0, Expr, Context, !Info) :-
	Expr0 = shorthand(ShorthandGoal),
	implicitly_quantify_goal_2_shorthand(ShorthandGoal, Context, Expr,
		!Info).

:- pred implicitly_quantify_goal_2_shorthand(shorthand_goal_expr::in,
	prog_context::in, hlds_goal_expr::out,
	quant_info::in, quant_info::out) is det.

implicitly_quantify_goal_2_shorthand(bi_implication(LHS0, RHS0), Context, Goal,
		!Info) :-

		% get the initial values of various settings
	quantification__get_quant_vars(QuantVars0, !Info),
	quantification__get_outside(OutsideVars0, !Info),
	quantification__get_lambda_outside(LambdaOutsideVars0, !Info),

		% quantified variables cannot be pushed inside a negation,
		% so we insert the quantified vars into the outside vars set,
		% and initialize the new quantified vars set to be empty
		% (the lambda outside vars remain unchanged)
	union(OutsideVars0, QuantVars0, OutsideVars1),
	init(QuantVars1),
	LambdaOutsideVars1 = LambdaOutsideVars0,
	quantification__set_quant_vars(QuantVars1, !Info),

		% prepare for quantifying the LHS:
		% add variables from the RHS to the outside vars
		% and the outside lambda vars sets.
	quantification__get_nonlocals_to_recompute(NonLocalsToRecompute, !Info),
	quantification__goal_vars(NonLocalsToRecompute, RHS0, RHS_Vars,
		RHS_LambdaVars),
	union(OutsideVars1, RHS_Vars, LHS_OutsideVars),
	union(LambdaOutsideVars1, RHS_LambdaVars, LHS_LambdaOutsideVars),

		% quantify the LHS
	quantification__set_outside(LHS_OutsideVars, !Info),
	quantification__set_lambda_outside(LHS_LambdaOutsideVars, !Info),
	implicitly_quantify_goal(LHS0, LHS, !Info),
	quantification__get_nonlocals(LHS_NonLocalVars, !Info),

		% prepare for quantifying the RHS:
		% add nonlocals from the LHS to the outside vars.
		% (We use the nonlocals rather than the more symmetric
		% approach of calling quantification__goal_vars on the
		% LHS goal because it is more efficient.)
	union(OutsideVars1, LHS_NonLocalVars, RHS_OutsideVars),
	RHS_LambdaOutsideVars = LambdaOutsideVars1,

		% quantify the RHS
	quantification__set_outside(RHS_OutsideVars, !Info),
	quantification__set_lambda_outside(RHS_LambdaOutsideVars, !Info),
	implicitly_quantify_goal(RHS0, RHS, !Info),
	quantification__get_nonlocals(RHS_NonLocalVars, !Info),

		% compute the nonlocals for this goal
	union(LHS_NonLocalVars, RHS_NonLocalVars, AllNonLocalVars),
	intersect(AllNonLocalVars, OutsideVars0, NonLocalVarsO),
	intersect(AllNonLocalVars, LambdaOutsideVars0, NonLocalVarsL),
	union(NonLocalVarsO, NonLocalVarsL, NonLocalVars),
	quantification__set_nonlocals(NonLocalVars, !Info),

		% restore the original values of various settings
	quantification__set_outside(OutsideVars0, !Info),
	quantification__set_lambda_outside(LambdaOutsideVars0, !Info),
	quantification__set_quant_vars(QuantVars0, !Info),

		%
		% We've figured out the quantification.
		% Now expand the bi-implication according to the usual
		% rules:
		%	LHS <=> RHS
		% ===>
		%	(LHS => RHS), (RHS => LHS)
		% ===>
		%	(not (LHS, not RHS)), (not (RHS, not LHS))
		%
	goal_info_init(GoalInfo0),
	goal_info_set_context(GoalInfo0, Context, GoalInfo1),
	quantification__set_goal_nonlocals(LHS_NonLocalVars,
		GoalInfo1, LHS_GI, !Info),
	quantification__set_goal_nonlocals(RHS_NonLocalVars,
		GoalInfo1, RHS_GI, !Info),
	quantification__set_goal_nonlocals(NonLocalVars,
		GoalInfo1, GI, !Info),
	NotLHS = not(LHS) - LHS_GI,
	NotRHS = not(RHS) - RHS_GI,
	ForwardsImplication = not(conj([LHS, NotRHS]) - GI) - GI,

		%
		% Rename apart the local variables of the goals
		% we've just duplicated.
		%
	ReverseImplication0 = not(conj([RHS, NotLHS]) - GI) - GI,
	quantification__goal_vars_bitset(NonLocalsToRecompute,
		ReverseImplication0, GoalVars),
	difference(GoalVars, NonLocalVars, RenameVars),
	quantification__rename_apart(RenameVars, _,
		ReverseImplication0, ReverseImplication, !Info),

	Goal = conj([ForwardsImplication, ReverseImplication]).

:- pred implicitly_quantify_atomic_goal(list(prog_var)::in,
	quant_info::in, quant_info::out) is det.

implicitly_quantify_atomic_goal(HeadVars, !Info) :-
	list_to_set(HeadVars, GoalVars),
	quantification__update_seen_vars(GoalVars, !Info),
	quantification__get_outside(OutsideVars, !Info),
	quantification__get_lambda_outside(LambdaOutsideVars, !Info),
	intersect(GoalVars, OutsideVars, NonLocals1),
	intersect(GoalVars, LambdaOutsideVars, NonLocals2),
	union(NonLocals1, NonLocals2, NonLocals),
	quantification__set_nonlocals(NonLocals, !Info).

:- pred implicitly_quantify_unify_rhs(maybe(list(bool))::in, prog_context::in,
	unify_rhs::in, unify_rhs::out, unification::in, unification::out,
	quant_info::in, quant_info::out) is det.

implicitly_quantify_unify_rhs(_, _, !RHS, !Unification, !Info) :-
	!.RHS = var(X),
	singleton_set(Vars, X),
	quantification__set_nonlocals(Vars, !Info).
implicitly_quantify_unify_rhs(ReuseArgs, _, !RHS, !Unification, !Info) :-
	!.RHS = functor(_, _, ArgVars),
	quantification__get_nonlocals_to_recompute(NonLocalsToRecompute,
		!Info),
	(
		NonLocalsToRecompute = code_gen_nonlocals,
		ReuseArgs = yes(SetArgs)
	->
		% The fields taken from the reused cell aren't
		% counted as code-gen nonlocals.
		quantification__get_updated_fields(SetArgs, ArgVars, Vars0),
		list_to_set(Vars0, Vars)
	;
		list_to_set(ArgVars, Vars)
	),
	quantification__set_nonlocals(Vars, !Info).
implicitly_quantify_unify_rhs(_, Context, !RHS, !Unification, !Info) :-
	!.RHS = lambda_goal(Purity, PredOrFunc, EvalMethod, FixModes,
		LambdaNonLocals0, LambdaVars0, Modes, Det, Goal0),
	!:RHS = lambda_goal(Purity, PredOrFunc, EvalMethod, FixModes,
		LambdaNonLocals, LambdaVars, Modes, Det, Goal),
	%
	% Note: make_hlds.m has already done most of the hard work for
	% lambda expressions. At this point, LambdaVars0 should in fact be
	% guaranteed to be fresh distinct variables. However, the code below
	% does not assume this.
	%
	quantification__get_outside(OutsideVars0, !Info),
	list_to_set(LambdaVars0, QVars),
		% Figure out which variables have overlapping scopes because
		% they occur outside the goal and are also lambda-quantified
		% vars.
	intersect(OutsideVars0, QVars, RenameVars0),
	( empty(RenameVars0) ->
		true
	;
		quantification__warn_overlapping_scope(RenameVars0, Context,
			!Info)
	),
		% We need to rename apart any of the lambda vars that
		% we have already seen, since they are new instances.
	quantification__get_seen(Seen0, !Info),
	intersect(Seen0, QVars, RenameVars1),

	union(RenameVars0, RenameVars1, RenameVars),
	quantification__rename_apart(RenameVars, RenameMap, Goal0, Goal1,
		!Info),
	goal_util__rename_var_list(LambdaVars0, no, RenameMap, LambdaVars),

		% Quantified variables cannot be pushed inside a lambda goal,
		% so we insert the quantified vars into the outside vars set,
		% and initialize the new quantified vars set to be empty.
	quantification__get_quant_vars(QuantVars0, !Info),
	union(OutsideVars0, QuantVars0, OutsideVars1),
	init(QuantVars),
	quantification__set_quant_vars(QuantVars, !Info),
		% Add the lambda vars as outside vars, since they are
		% outside of the lambda goal
	insert_list(OutsideVars1, LambdaVars, OutsideVars),
	quantification__set_outside(OutsideVars, !Info),
		% Set the LambdaOutsideVars set to empty, because
		% variables that occur outside this lambda expression
		% only in other lambda expressions should not be
		% considered non-local.
	quantification__get_lambda_outside(LambdaOutsideVars0, !Info),
	init(LambdaOutsideVars),
	quantification__set_lambda_outside(LambdaOutsideVars, !Info),
	implicitly_quantify_goal(Goal1, Goal, !Info),

	quantification__get_nonlocals(NonLocals0, !Info),
		% lambda-quantified variables are local
	delete_list(NonLocals0, LambdaVars, NonLocals),
	quantification__set_quant_vars(QuantVars0, !Info),
	quantification__set_outside(OutsideVars0, !Info),
	quantification__set_lambda_outside(LambdaOutsideVars0, !Info),
	quantification__set_nonlocals(NonLocals, !Info),

	%
	% Work out the list of non-local curried arguments to the lambda
	% expression. This set must only ever decrease, since the first
	% approximation that make_hlds uses includes all variables in the
	% lambda expression except the quantified variables.
	%
	Goal = _ - LambdaGoalInfo,
	goal_info_get_nonlocals(LambdaGoalInfo, LambdaGoalNonLocals),
	list__filter(contains(LambdaGoalNonLocals),
		LambdaNonLocals0, LambdaNonLocals),

	%
	% For a unification that constructs a lambda expression,
	% the argument variables of the construction are the non-local
	% variables of the lambda expression.  So if we recompute the
	% non-locals, we need to recompute the argument variables of
	% the construction, and hence we also need to recompute their modes.
	% The non-locals set must only ever decrease, not increase,
	% so we can just use the old modes.
	%
	(
		!.Unification = construct(ConstructVar, ConsId, Args0,
			ArgModes0, HowToConstruct, Uniq, Size)
	->
		require(unify(Size, no), "lambda term has size info"),
		map__from_corresponding_lists(Args0, ArgModes0, ArgModesMap),
		to_sorted_list(NonLocals, Args),
		map__apply_to_list(Args, ArgModesMap, ArgModes),
		!:Unification = construct(ConstructVar, ConsId, Args,
			ArgModes, HowToConstruct, Uniq, Size)
	;
		% after mode analysis, unifications with lambda variables
		% should always be construction unifications, but
		% quantification gets invoked before mode analysis,
		% so we need to allow this case...
		true
	).

:- pred implicitly_quantify_conj(list(hlds_goal)::in, list(hlds_goal)::out,
	quant_info::in, quant_info::out) is det.

implicitly_quantify_conj(!Goals, !Info) :-
	quantification__get_nonlocals_to_recompute(NonLocalsToRecompute,
		!Info),
	get_vars(NonLocalsToRecompute, !.Goals, FollowingVarsList),
	implicitly_quantify_conj_2(FollowingVarsList, !Goals, !Info).

:- pred implicitly_quantify_conj_2(list(pair(set_of_var))::in,
	list(hlds_goal)::in, list(hlds_goal)::out,
	quant_info::in, quant_info::out) is det.

implicitly_quantify_conj_2(_, [], [], !Info) :-
	init(NonLocalVars),
	quantification__set_nonlocals(NonLocalVars, !Info).
implicitly_quantify_conj_2([], [_ | _], _, _, _) :-
	error("implicitly_quantify_conj_2: length mismatch").
implicitly_quantify_conj_2(
		[FollowingVars - LambdaFollowingVars | FollowingVarsList],
		[Goal0 | Goals0], [Goal | Goals], !Info) :-
	quantification__get_outside(OutsideVars, !Info),
	quantification__get_lambda_outside(LambdaOutsideVars, !Info),
	union(OutsideVars, FollowingVars, OutsideVars1),
	union(LambdaOutsideVars, LambdaFollowingVars, LambdaOutsideVars1),
	quantification__set_outside(OutsideVars1, !Info),
	quantification__set_lambda_outside(LambdaOutsideVars1, !Info),
	implicitly_quantify_goal(Goal0, Goal, !Info),
	quantification__get_nonlocals(NonLocalVars1, !Info),
	union(OutsideVars, NonLocalVars1, OutsideVars2),
	quantification__set_outside(OutsideVars2, !Info),
	quantification__set_lambda_outside(LambdaOutsideVars, !Info),
	implicitly_quantify_conj_2(FollowingVarsList, Goals0, Goals, !Info),
	quantification__get_nonlocals(NonLocalVars2, !Info),
	union(NonLocalVars1, NonLocalVars2, NonLocalVarsConj),
	intersect(NonLocalVarsConj, OutsideVars, NonLocalVarsO),
	intersect(NonLocalVarsConj, LambdaOutsideVars, NonLocalVarsL),
	union(NonLocalVarsO, NonLocalVarsL, NonLocalVars),
	quantification__set_outside(OutsideVars, !Info),
	quantification__set_nonlocals(NonLocalVars, !Info).

:- pred implicitly_quantify_disj(list(hlds_goal)::in, list(hlds_goal)::out,
	quant_info::in, quant_info::out) is det.

implicitly_quantify_disj([], [], !Info) :-
	init(NonLocalVars),
	quantification__set_nonlocals(NonLocalVars, !Info).
implicitly_quantify_disj([Goal0 | Goals0], [Goal | Goals], !Info) :-
	implicitly_quantify_goal(Goal0, Goal, !Info),
	quantification__get_nonlocals(NonLocalVars0, !Info),
	implicitly_quantify_disj(Goals0, Goals, !Info),
	quantification__get_nonlocals(NonLocalVars1, !Info),
	union(NonLocalVars0, NonLocalVars1, NonLocalVars),
	quantification__set_nonlocals(NonLocalVars, !Info).

:- pred implicitly_quantify_cases(list(case)::in, list(case)::out,
	quant_info::in, quant_info::out) is det.

implicitly_quantify_cases([], [], !Info) :-
	init(NonLocalVars),
	quantification__set_nonlocals(NonLocalVars, !Info).
implicitly_quantify_cases([case(Cons, Goal0) | Cases0],
		[case(Cons, Goal) | Cases], !Info) :-
	implicitly_quantify_goal(Goal0, Goal, !Info),
	quantification__get_nonlocals(NonLocalVars0, !Info),
	implicitly_quantify_cases(Cases0, Cases, !Info),
	quantification__get_nonlocals(NonLocalVars1, !Info),
	union(NonLocalVars0, NonLocalVars1, NonLocalVars),
	quantification__set_nonlocals(NonLocalVars, !Info).

%-----------------------------------------------------------------------------%

	% insert the given set of variables into the set of `seen' variables.

:- pred quantification__update_seen_vars(set_of_var::in,
	quant_info::in, quant_info::out) is det.

quantification__update_seen_vars(NewVars, !Info) :-
	quantification__get_seen(SeenVars0, !Info),
	union(SeenVars0, NewVars, SeenVars),
	quantification__set_seen(SeenVars, !Info).

%-----------------------------------------------------------------------------%

	% Given a list of goals, produce a corresponding list of
	% following variables, where the following variables
	% for each goal are those variables which occur free in any of the
	% following goals in the list.  The following variables
	% are divided into a pair of sets: the first set
	% contains following variables that occur not in lambda goals,
	% and the second contains following variables that
	% occur in lambda goals.

:- pred get_vars(nonlocals_to_recompute::in, list(hlds_goal)::in,
	list(pair(set_of_var))::out) is det.

get_vars(_, [], []).
get_vars(NonLocalsToRecompute, [_Goal | Goals],
		[Set - LambdaSet | SetPairs]) :-
	get_vars_2(NonLocalsToRecompute, Goals, Set, LambdaSet, SetPairs).

:- pred get_vars_2(nonlocals_to_recompute::in, list(hlds_goal)::in,
	set_of_var::out, set_of_var::out, list(pair(set_of_var))::out) is det.

get_vars_2(_, [], Set, LambdaSet, []) :-
	init(Set),
	init(LambdaSet).
get_vars_2(NonLocalsToRecompute, [Goal | Goals],
		Set, LambdaSet, SetPairList) :-
	get_vars_2(NonLocalsToRecompute, Goals,
		Set0, LambdaSet0, SetPairList0),
	quantification__goal_vars(NonLocalsToRecompute,
		Goal, Set1, LambdaSet1),
	union(Set0, Set1, Set),
	union(LambdaSet0, LambdaSet1, LambdaSet),
	SetPairList = [Set0 - LambdaSet0 | SetPairList0].

:- pred goal_list_vars_2(nonlocals_to_recompute::in, list(hlds_goal)::in,
	set_of_var::in, set_of_var::out, set_of_var::in, set_of_var::out)
	is det.

goal_list_vars_2(_, [], !Set, !LambdaSet).
goal_list_vars_2(NonLocalsToRecompute, [Goal - _GoalInfo| Goals],
		!Set, !LambdaSet) :-
	quantification__goal_vars_2(NonLocalsToRecompute, Goal,
		!Set, !LambdaSet),
	goal_list_vars_2(NonLocalsToRecompute, Goals, !Set, !LambdaSet).

:- pred case_list_vars_2(nonlocals_to_recompute::in, list(case)::in,
	set_of_var::in, set_of_var::out, set_of_var::in, set_of_var::out)
	is det.

case_list_vars_2(_, [], !Set, !LambdaSet).
case_list_vars_2(NonLocalsToRecompute, [case(_Cons, Goal - _GoalInfo) | Cases],
		!Set, !LambdaSet) :-
	quantification__goal_vars_2(NonLocalsToRecompute, Goal,
		!Set, !LambdaSet),
	case_list_vars_2(NonLocalsToRecompute, Cases, !Set, !LambdaSet).

	% quantification__goal_vars(NonLocalsToRecompute, Goal, Vars):
	%	Vars is the set of variables that occur free (unquantified)
	%	in Goal, excluding unset fields of reconstructions if
	%	NonLocalsToRecompute is `code_gen_nonlocals'.
quantification__goal_vars(NonLocalsToRecompute, Goal,
		bitset_to_set(BothSet)) :-
	quantification__goal_vars_bitset(NonLocalsToRecompute,
		Goal, BothSet).

quantification__goal_vars(Goal, BothSet) :-
	quantification__goal_vars(ordinary_nonlocals, Goal, BothSet).

:- pred quantification__goal_vars_bitset(nonlocals_to_recompute::in,
	hlds_goal::in, set_of_var::out) is det.

quantification__goal_vars_bitset(NonLocalsToRecompute, Goal, BothSet) :-
	quantification__goal_vars(NonLocalsToRecompute, Goal, Set, LambdaSet),
	BothSet = union(Set, LambdaSet).

	% quantification__goal_vars(Goal, NonLambdaSet, LambdaSet):
	%	Set is the set of variables that occur free (unquantified)
	%	in Goal, not counting occurrences in lambda expressions.
	%	LambdaSet is the set of variables that occur free (unquantified)
	%	in lambda expressions in Goal.
:- pred quantification__goal_vars(nonlocals_to_recompute::in,
	hlds_goal::in, set_of_var::out, set_of_var::out) is det.

quantification__goal_vars(NonLocalsToRecompute, Goal - _GoalInfo,
		Set, LambdaSet) :-
	init(Set0),
	init(LambdaSet0),
	quantification__goal_vars_2(NonLocalsToRecompute,
		Goal, Set0, Set, LambdaSet0, LambdaSet).

:- pred quantification__goal_vars_2(nonlocals_to_recompute::in,
	hlds_goal_expr::in,
	set_of_var::in, set_of_var::out,
	set_of_var::in, set_of_var::out) is det.

quantification__goal_vars_2(NonLocalsToRecompute,
		unify(LHS, RHS, _, Unification, _), !Set, !LambdaSet) :-
	insert(!.Set, LHS, !:Set),
	( Unification = construct(_, _, _, _, How, _, Size) ->
		( How = reuse_cell(cell_to_reuse(ReuseVar, _, SetArgs)) ->
			MaybeSetArgs = yes(SetArgs),
			insert(!.Set, ReuseVar, !:Set)
		;
			MaybeSetArgs = no
		),
		( Size = yes(dynamic_size(SizeVar)) ->
			insert(!.Set, SizeVar, !:Set)
		;
			true
		)
	; Unification = complicated_unify(_, _, TypeInfoVars) ->
		MaybeSetArgs = no,
		insert_list(!.Set, TypeInfoVars, !:Set)
	;
		MaybeSetArgs = no
	),
	quantification__unify_rhs_vars(NonLocalsToRecompute, RHS, MaybeSetArgs,
		!Set, !LambdaSet).

quantification__goal_vars_2(_, generic_call(GenericCall, ArgVars1, _, _),
		!Set, !LambdaSet) :-
	goal_util__generic_call_vars(GenericCall, ArgVars0),
	insert_list(!.Set, ArgVars0, !:Set),
	insert_list(!.Set, ArgVars1, !:Set).

quantification__goal_vars_2(_, call(_, _, ArgVars, _, _, _),
		!Set, !LambdaSet) :-
	insert_list(!.Set, ArgVars, !:Set).

quantification__goal_vars_2(NonLocalsToRecompute, conj(Goals),
		!Set, !LambdaSet) :-
	goal_list_vars_2(NonLocalsToRecompute, Goals, !Set, !LambdaSet).

quantification__goal_vars_2(NonLocalsToRecompute, par_conj(Goals),
		!Set, !LambdaSet) :-
	goal_list_vars_2(NonLocalsToRecompute, Goals,
		!Set, !LambdaSet).

quantification__goal_vars_2(NonLocalsToRecompute, disj(Goals),
		!Set, !LambdaSet) :-
	goal_list_vars_2(NonLocalsToRecompute, Goals,
		!Set, !LambdaSet).

quantification__goal_vars_2(NonLocalsToRecompute, switch(Var, _Det, Cases),
		!Set, !LambdaSet) :-
	insert(!.Set, Var, !:Set),
	case_list_vars_2(NonLocalsToRecompute, Cases, !Set, !LambdaSet).

quantification__goal_vars_2(NonLocalsToRecompute, some(Vars, _, Goal),
		Set0, Set, LambdaSet0, LambdaSet) :-
	quantification__goal_vars(NonLocalsToRecompute,
		Goal, Set1, LambdaSet1),
	delete_list(Set1, Vars, Set2),
	delete_list(LambdaSet1, Vars, LambdaSet2),
	union(Set0, Set2, Set),
	union(LambdaSet0, LambdaSet2, LambdaSet).

quantification__goal_vars_2(NonLocalsToRecompute, not(Goal - _GoalInfo),
		!Set, !LambdaSet) :-
	quantification__goal_vars_2(NonLocalsToRecompute, Goal,
		!Set, !LambdaSet).

quantification__goal_vars_2(NonLocalsToRecompute,
		if_then_else(Vars, Cond, Then, Else),
		!Set, !LambdaSet) :-
	% This code does the following:
	%     !:Set = !.Set + ( (vars(Cond) + vars(Then)) \ Vars ) + vars(Else)
	% where `+' is set union and `\' is relative complement.
	quantification__goal_vars(NonLocalsToRecompute, Cond,
		CondSet, CondLambdaSet),
	quantification__goal_vars(NonLocalsToRecompute, Then,
		ThenSet, ThenLambdaSet),
	quantification__goal_vars(NonLocalsToRecompute, Else,
		ElseSet, ElseLambdaSet),
	union(CondSet, ThenSet, CondThenSet),
	union(CondLambdaSet, ThenLambdaSet, CondThenLambdaSet),
	delete_list(CondThenSet, Vars, SomeCondThenSet),
	delete_list(CondThenLambdaSet, Vars, SomeCondThenLambdaSet),
	union(!.Set, SomeCondThenSet, !:Set),
	union(!.LambdaSet, SomeCondThenLambdaSet, !:LambdaSet),
	union(!.Set, ElseSet, !:Set),
	union(!.LambdaSet, ElseLambdaSet, !:LambdaSet).

quantification__goal_vars_2(_, foreign_proc(_, _, _, Args, ExtraArgs, _),
		!Set, !LambdaSet) :-
	Vars = list__map(foreign_arg_var, Args),
	ExtraVars = list__map(foreign_arg_var, ExtraArgs),
	list__append(Vars, ExtraVars, AllVars),
	insert_list(!.Set, AllVars, !:Set).

quantification__goal_vars_2(NonLocalsToRecompute, shorthand(ShorthandGoal),
		!Set, !LambdaSet) :-
	quantification__goal_vars_2_shorthand(NonLocalsToRecompute,
		ShorthandGoal, !Set, !LambdaSet).

:- pred quantification__goal_vars_2_shorthand(nonlocals_to_recompute::in,
	shorthand_goal_expr::in, set_of_var::in, set_of_var::out,
	set_of_var::in, set_of_var::out) is det.

quantification__goal_vars_2_shorthand(NonLocalsToRecompute,
		bi_implication(LHS, RHS), !Set, !LambdaSet) :-
	goal_list_vars_2(NonLocalsToRecompute, [LHS, RHS],
		!Set, !LambdaSet).

:- pred quantification__unify_rhs_vars(nonlocals_to_recompute::in,
	unify_rhs::in, maybe(list(bool))::in, set_of_var::in, set_of_var::out,
	set_of_var::in, set_of_var::out) is det.

quantification__unify_rhs_vars(_, var(Y), _, !Set, !LambdaSet) :-
	insert(!.Set, Y, !:Set).
quantification__unify_rhs_vars(NonLocalsToRecompute, functor(_, _, ArgVars),
		MaybeSetArgs, !Set, !LambdaSet) :-
	(
		NonLocalsToRecompute = code_gen_nonlocals,
		MaybeSetArgs = yes(SetArgs)
	->
		% Ignore the fields taken from the reused cell.
		quantification__get_updated_fields(SetArgs, ArgVars,
			ArgsToSet),
		insert_list(!.Set, ArgsToSet, !:Set)
	;
		insert_list(!.Set, ArgVars, !:Set)
	).
quantification__unify_rhs_vars(NonLocalsToRecompute,
		lambda_goal(_, _, _, _, _, LambdaVars, _, _, Goal), _,
		!Set, !LambdaSet) :-
	% Note that the NonLocals list is not counted, since all the
	% variables in that list must occur in the goal.
	quantification__goal_vars_bitset(NonLocalsToRecompute, Goal, GoalVars),
	delete_list(GoalVars, LambdaVars, GoalVars1),
	union(!.LambdaSet, GoalVars1, !:LambdaSet).

:- pred quantification__insert_set_fields(list(bool)::in, list(prog_var)::in,
	set_of_var::in, set_of_var::out) is det.

quantification__insert_set_fields(SetArgs, Args, !Set) :-
	quantification__get_updated_fields(SetArgs, Args,  ArgsToSet),
	insert_list(!.Set, ArgsToSet, !:Set).

:- pred quantification__get_updated_fields(list(bool)::in,
	list(prog_var)::in, list(prog_var)::out) is det.

quantification__get_updated_fields(SetArgs, Args, ArgsToSet) :-
	quantification__get_updated_fields(SetArgs, Args, [], ArgsToSet).

:- pred quantification__get_updated_fields(list(bool)::in,
	list(prog_var)::in, list(prog_var)::in, list(prog_var)::out) is det.

quantification__get_updated_fields([], [], !ArgsToSet).
quantification__get_updated_fields([], [_|_], _, _) :-
	error("quantification__get_updated_fields").
quantification__get_updated_fields([_|_], [], _, _) :-
	error("quantification__get_updated_fields").
quantification__get_updated_fields([SetArg | SetArgs], [Arg | Args],
		!ArgsToSet) :-
	(
		SetArg = yes,
		!:ArgsToSet = [Arg | !.ArgsToSet]
	;
		SetArg = no,
		!:ArgsToSet = !.ArgsToSet
	),
	quantification__get_updated_fields(SetArgs, Args, !ArgsToSet).

:- func quantification__get_unify_typeinfos(unification) = list(prog_var).

quantification__get_unify_typeinfos(Unification) =
	( Unification = complicated_unify(_, _, TypeInfoVars0) ->
		TypeInfoVars0
	;
		[]
	).

%-----------------------------------------------------------------------------%

:- pred quantification__warn_overlapping_scope(set_of_var::in,
	prog_context::in, quant_info::in, quant_info::out) is det.

quantification__warn_overlapping_scope(OverlapVars, Context, !Info) :-
	to_sorted_list(OverlapVars, Vars),
	quantification__get_warnings(Warnings0, !Info),
	Warnings = [warn_overlap(Vars, Context) | Warnings0],
	quantification__set_warnings(Warnings, !Info).

%-----------------------------------------------------------------------------%

% quantification__rename_apart(RenameSet, RenameMap, Goal0, Goal):
%	For each variable V in RenameSet, create a fresh variable V',
%	and insert the mapping V->V' into RenameMap.
%	Apply RenameMap to Goal0 giving Goal.

:- pred quantification__rename_apart(set_of_var::in,
	map(prog_var, prog_var)::out, hlds_goal::in, hlds_goal::out,
	quant_info::in, quant_info::out) is det.

quantification__rename_apart(RenameSet, RenameMap, !Goal, !Info) :-
	quantification__get_nonlocals_to_recompute(NonLocalsToRecompute,
		!Info),
	(
		%
		% Don't rename apart variables when recomputing the
		% code-gen nonlocals -- that would stuff up the
		% ordinary non-locals and the mode information.
		% The ordinary non-locals are always recomputed
		% before the code-gen nonlocals -- any necessary
		% renaming will have been done while recomputing
		% the ordinary non-locals.
		%
		( empty(RenameSet)
		; NonLocalsToRecompute = code_gen_nonlocals
		)
	->
		map__init(RenameMap)
	;
		to_sorted_list(RenameSet, RenameList),
		quantification__get_varset(Varset0, !Info),
		quantification__get_vartypes(VarTypes0, !Info),
		map__init(RenameMap0),
		goal_util__create_variables(RenameList, Varset0, VarTypes0,
							%^ Reference ^Var names
			Varset0, Varset, VarTypes0, VarTypes,
			RenameMap0, RenameMap),
		goal_util__rename_vars_in_goal(!.Goal, RenameMap, !:Goal),
		quantification__set_varset(Varset, !Info),
		quantification__set_vartypes(VarTypes, !Info)

		% We don't need to add the newly created vars to the seen vars
		% because we won't find them anywhere else in the enclosing
		% goal. This is a performance improvement because it keeps
		% the size of the seen var set down.
		% quantification__get_seen(SeenVars0, !Info),
		% map__values(RenameMap, NewVarsList),
		% insert_list(SeenVars0, NewVarsList, SeenVars),
		% quantification__set_seen(SeenVars, !Info)
	).

%-----------------------------------------------------------------------------%

:- pred quantification__set_goal_nonlocals(set_of_var::in,
	hlds_goal_info::in, hlds_goal_info::out,
	quant_info::in, quant_info::out) is det.

quantification__set_goal_nonlocals(NonLocals, !GoalInfo, !Info) :-
	quantification__set_goal_nonlocals(NonLocals, _, !GoalInfo,
		!Info).

:- pred quantification__set_goal_nonlocals(set_of_var::in, set(prog_var)::out,
	hlds_goal_info::in, hlds_goal_info::out,
	quant_info::in, quant_info::out) is det.

quantification__set_goal_nonlocals(NonLocals0, NonLocals, !GoalInfo, !Info) :-
	NonLocals = bitset_to_set(NonLocals0),
	quantification__get_nonlocals_to_recompute(NonLocalsToRecompute,
		!Info),
	(
		NonLocalsToRecompute = ordinary_nonlocals,
		goal_info_set_nonlocals(!.GoalInfo, NonLocals, !:GoalInfo)
	;
		NonLocalsToRecompute = code_gen_nonlocals,
		goal_info_set_code_gen_nonlocals(!.GoalInfo, NonLocals,
			!:GoalInfo)
	).

%-----------------------------------------------------------------------------%

:- func bitset_to_set(set_of_var) = set(prog_var).
:- func set_to_bitset(set(prog_var)) = set_of_var.

bitset_to_set(Bitset) = set__sorted_list_to_set(to_sorted_list(Bitset)).
set_to_bitset(Bitset) = sorted_list_to_set(set__to_sorted_list(Bitset)).

%-----------------------------------------------------------------------------%

:- pred quantification__init(nonlocals_to_recompute::in, set_of_var::in,
	prog_varset::in, vartypes::in, quant_info::out) is det.

quantification__init(RecomputeNonLocals, OutsideVars,
		Varset, VarTypes, QuantInfo) :-
	OverlapWarnings = [],
	QuantInfo = quant_info(RecomputeNonLocals, OutsideVars, QuantVars,
		LambdaOutsideVars, NonLocals, Seen, Varset, VarTypes,
		OverlapWarnings),
	init(QuantVars),
	init(NonLocals),
	init(LambdaOutsideVars),
	Seen = OutsideVars.

:- pred quantification__get_nonlocals_to_recompute(nonlocals_to_recompute::out,
	quant_info::in, quant_info::out) is det.

:- pred quantification__get_outside(set_of_var::out,
	quant_info::in, quant_info::out) is det.

:- pred quantification__get_quant_vars(set_of_var::out,
	quant_info::in, quant_info::out) is det.

:- pred quantification__get_lambda_outside(set_of_var::out,
	quant_info::in, quant_info::out) is det.

:- pred quantification__get_nonlocals(set_of_var::out,
	quant_info::in, quant_info::out) is det.

:- pred quantification__get_seen(set_of_var::out,
	quant_info::in, quant_info::out) is det.

:- pred quantification__get_varset(prog_varset::out,
	quant_info::in, quant_info::out) is det.

:- pred quantification__get_vartypes(vartypes::out,
	quant_info::in, quant_info::out) is det.

:- pred quantification__get_warnings(list(quant_warning)::out,
	quant_info::in, quant_info::out) is det.

:- pred quantification__set_outside(set_of_var::in,
	quant_info::in, quant_info::out) is det.

:- pred quantification__set_quant_vars(set_of_var::in,
	quant_info::in, quant_info::out) is det.

:- pred quantification__set_lambda_outside(set_of_var::in,
	quant_info::in, quant_info::out) is det.

:- pred quantification__set_nonlocals(set_of_var::in,
	quant_info::in, quant_info::out) is det.

:- pred quantification__set_seen(set_of_var::in,
	quant_info::in, quant_info::out) is det.

:- pred quantification__set_varset(prog_varset::in,
	quant_info::in, quant_info::out) is det.

:- pred quantification__set_vartypes(vartypes::in,
	quant_info::in, quant_info::out) is det.

:- pred quantification__set_warnings(list(quant_warning)::in,
	quant_info::in, quant_info::out) is det.

quantification__get_nonlocals_to_recompute(Q ^ nonlocals_to_recompute, Q, Q).
quantification__get_outside(Q ^ outside, Q, Q).
quantification__get_quant_vars(Q ^ quant_vars, Q, Q).
quantification__get_lambda_outside(Q ^ lambda_outside, Q, Q).
quantification__get_nonlocals(Q ^ nonlocals, Q, Q).
quantification__get_seen(Q ^ seen, Q, Q).
quantification__get_varset(Q ^ varset, Q, Q).
quantification__get_vartypes(Q ^ vartypes, Q, Q).
quantification__get_warnings(Q ^ warnings, Q, Q).

quantification__set_outside(Outside, Q0, Q0 ^ outside := Outside).
quantification__set_quant_vars(QuantVars, Q0, Q0 ^ quant_vars := QuantVars).
quantification__set_lambda_outside(LambdaOutsideVars, Q0,
	Q0 ^ lambda_outside := LambdaOutsideVars).
quantification__set_nonlocals(NonLocals, Q0, Q0 ^ nonlocals := NonLocals).
quantification__set_seen(Seen, Q0, Q0 ^ seen := Seen).
quantification__set_varset(Varset, Q0, Q0 ^ varset := Varset).
quantification__set_vartypes(VarTypes, Q0, Q0 ^ vartypes := VarTypes).
quantification__set_warnings(Warnings, Q0, Q0 ^ warnings := Warnings).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
