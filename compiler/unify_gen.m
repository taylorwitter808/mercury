%---------------------------------------------------------------------------%
% Copyright (C) 1994-2005 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% This module handles code generation for "simple" unifications,
% i.e. those unifications which are simple enough for us to generate
% inline code.
%
% For "complicated" unifications, we generate a call to an out-of-line
% unification predicate (the call is handled in call_gen.m) - and then
% eventually generate the out-of-line code (unify_proc.m).
%
%---------------------------------------------------------------------------%

:- module ll_backend__unify_gen.

:- interface.

:- import_module hlds__code_model.
:- import_module hlds__hlds_goal.
:- import_module ll_backend__code_info.
:- import_module ll_backend__llds.
:- import_module parse_tree__prog_data.

:- type test_sense
	--->	branch_on_success
	;	branch_on_failure.

:- pred unify_gen__generate_unification(code_model::in, unification::in,
	hlds_goal_info::in, code_tree::out, code_info::in, code_info::out)
	is det.

:- pred unify_gen__generate_tag_test(prog_var::in, cons_id::in, test_sense::in,
	label::out, code_tree::out, code_info::in, code_info::out) is det.

%---------------------------------------------------------------------------%

:- implementation.

:- import_module aditi_backend__rl.
:- import_module backend_libs__builtin_ops.
:- import_module backend_libs__proc_label.
:- import_module backend_libs__rtti.
:- import_module backend_libs__type_class_info.
:- import_module check_hlds__mode_util.
:- import_module check_hlds__type_util.
:- import_module hlds__arg_info.
:- import_module hlds__hlds_data.
:- import_module hlds__hlds_module.
:- import_module hlds__hlds_out.
:- import_module hlds__hlds_pred.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module libs__tree.
:- import_module ll_backend__code_aux.
:- import_module ll_backend__code_util.
:- import_module ll_backend__continuation_info.
:- import_module ll_backend__layout.
:- import_module ll_backend__stack_layout.
:- import_module parse_tree__error_util.
:- import_module parse_tree__prog_data.
:- import_module parse_tree__prog_out.
:- import_module parse_tree__prog_type.
:- import_module mdbcomp__prim_data.

:- import_module bool.
:- import_module int.
:- import_module list.
:- import_module map.
:- import_module require.
:- import_module std_util.
:- import_module string.
:- import_module term.

:- type uni_val		--->	ref(prog_var)
			;	lval(lval).

%---------------------------------------------------------------------------%

unify_gen__generate_unification(CodeModel, Uni, GoalInfo, Code, !CI) :-
	( CodeModel = model_non ->
		error("nondet unification in unify_gen__generate_unification")
	;
		true
	),
	(
		Uni = assign(Left, Right),
		( code_info__variable_is_forward_live(!.CI, Left) ->
			unify_gen__generate_assignment(Left, Right, Code, !CI)
		;
			Code = empty
		)
	;
		Uni = construct(Var, ConsId, Args, Modes, _, _, Size),
		( code_info__variable_is_forward_live(!.CI, Var) ->
			unify_gen__generate_construction(Var, ConsId,
				Args, Modes, Size, GoalInfo, Code, !CI)
		;
			Code = empty
		)
	;
		Uni = deconstruct(Var, ConsId, Args, Modes, _CanFail, _CanCGC),
		( CodeModel = model_det ->
			unify_gen__generate_det_deconstruction(Var, ConsId,
				Args, Modes, Code, !CI)
		;
			unify_gen__generate_semi_deconstruction(Var, ConsId,
				Args, Modes, Code, !CI)
		)
	;
		Uni = simple_test(Var1, Var2),
		( CodeModel = model_det ->
			error("det simple_test during code generation")
		;
			unify_gen__generate_test(Var1, Var2, Code, !CI)
		)
	;
			% These should have been transformed into calls
			% to unification procedures by polymorphism.m.
		Uni = complicated_unify(_UniMode, _CanFail, _TypeInfoVars),
		error("complicated unify during code generation")
	).

%---------------------------------------------------------------------------%

	% assignment unifications are generated by simply caching the
	% bound variable as the expression that generates the free
	% variable. No immediate code is generated.

:- pred unify_gen__generate_assignment(prog_var::in, prog_var::in,
	code_tree::out, code_info::in, code_info::out) is det.

unify_gen__generate_assignment(VarA, VarB, empty, !CI) :-
	( code_info__variable_is_forward_live(!.CI, VarA) ->
		code_info__assign_var_to_var(VarA, VarB, !CI)
	;
		% For free-free unifications, the mode analysis reports
		% them as assignment to the dead variable. For such
		% unifications we of course don't generate any code.
		true
	).

%---------------------------------------------------------------------------%

	% A [simple] test unification is generated by flushing both
	% variables from the cache, and producing code that branches
	% to the fall-through point if the two values are not the same.
	% Simple tests are in-in unifications on enumerations, integers,
	% strings and floats.

:- pred unify_gen__generate_test(prog_var::in, prog_var::in, code_tree::out,
	code_info::in, code_info::out) is det.

unify_gen__generate_test(VarA, VarB, Code, !CI) :-
	code_info__produce_variable(VarA, CodeA, ValA, !CI),
	code_info__produce_variable(VarB, CodeB, ValB, !CI),
	CodeAB = tree(CodeA, CodeB),
	Type = code_info__variable_type(!.CI, VarA),
	( Type = term__functor(term__atom("string"), [], _) ->
		Op = str_eq
	; Type = term__functor(term__atom("float"), [], _) ->
		Op = float_eq
	;
		Op = eq
	),
	code_info__fail_if_rval_is_false(binop(Op, ValA, ValB), FailCode, !CI),
	Code = tree(CodeAB, FailCode).

%---------------------------------------------------------------------------%

unify_gen__generate_tag_test(Var, ConsId, Sense, ElseLab, Code, !CI) :-
	code_info__produce_variable(Var, VarCode, Rval, !CI),
	%
	% As an optimization, for data types with exactly two alternatives,
	% one of which is a constant, we make sure that we test against the
	% constant (negating the result of the test, if needed),
	% since a test against a constant is cheaper than a tag test.
	%
	(
		ConsId = cons(_, Arity),
		Arity > 0
	->
		Type = code_info__variable_type(!.CI, Var),
		TypeDefn = code_info__lookup_type_defn(!.CI, Type),
		hlds_data__get_type_defn_body(TypeDefn, TypeBody),
		( ConsTable = TypeBody ^ du_type_cons_tag_values ->
			map__to_assoc_list(ConsTable, ConsList),
			(
				ConsList = [ConsId - _, OtherConsId - _],
				OtherConsId = cons(_, 0)
			->
				Reverse = yes(OtherConsId)
			;
				ConsList = [OtherConsId - _, ConsId - _],
				OtherConsId = cons(_, 0)
			->
				Reverse = yes(OtherConsId)
			;
				Reverse = no
			)
		;
			Reverse = no
		)
	;
		Reverse = no
	),
	VarName = code_info__variable_to_string(!.CI, Var),
	ConsIdName = hlds_out__cons_id_to_string(ConsId),
	(
		Reverse = no,
		string__append_list(["checking that ", VarName,
			" has functor ", ConsIdName], Comment),
		CommentCode = node([comment(Comment) - ""]),
		Tag = code_info__cons_id_to_tag(!.CI, Var, ConsId),
		unify_gen__generate_tag_test_rval_2(Tag, Rval, TestRval)
	;
		Reverse = yes(TestConsId),
		string__append_list(["checking that ", VarName,
			" has functor ", ConsIdName, " (inverted test)"],
			Comment),
		CommentCode = node([comment(Comment) - ""]),
		Tag = code_info__cons_id_to_tag(!.CI, Var, TestConsId),
		unify_gen__generate_tag_test_rval_2(Tag, Rval, NegTestRval),
		code_util__neg_rval(NegTestRval, TestRval)
	),
	code_info__get_next_label(ElseLab, !CI),
	(
		Sense = branch_on_success,
		TheRval = TestRval
	;
		Sense = branch_on_failure,
		code_util__neg_rval(TestRval, TheRval)
	),
	TestCode = node([
		if_val(TheRval, label(ElseLab)) - "tag test"
	]),
	Code = tree(VarCode, tree(CommentCode, TestCode)).

%---------------------------------------------------------------------------%

:- pred unify_gen__generate_tag_test_rval(prog_var::in, cons_id::in,
	rval::out, code_tree::out, code_info::in, code_info::out) is det.

unify_gen__generate_tag_test_rval(Var, ConsId, TestRval, Code, !CI) :-
	code_info__produce_variable(Var, Code, Rval, !CI),
	Tag = code_info__cons_id_to_tag(!.CI, Var, ConsId),
	unify_gen__generate_tag_test_rval_2(Tag, Rval, TestRval).

:- pred unify_gen__generate_tag_test_rval_2(cons_tag::in, rval::in, rval::out)
	is det.

unify_gen__generate_tag_test_rval_2(string_constant(String), Rval, TestRval) :-
	TestRval = binop(str_eq, Rval, const(string_const(String))).
unify_gen__generate_tag_test_rval_2(float_constant(Float), Rval, TestRval) :-
	TestRval = binop(float_eq, Rval, const(float_const(Float))).
unify_gen__generate_tag_test_rval_2(int_constant(Int), Rval, TestRval) :-
	TestRval = binop(eq, Rval, const(int_const(Int))).
unify_gen__generate_tag_test_rval_2(pred_closure_tag(_, _, _), _Rval,
		_TestRval) :-
	% This should never happen, since the error will be detected
	% during mode checking.
	error("Attempted higher-order unification").
unify_gen__generate_tag_test_rval_2(type_ctor_info_constant(_, _, _), _, _) :-
	% This should never happen
	error("Attempted type_ctor_info unification").
unify_gen__generate_tag_test_rval_2(base_typeclass_info_constant(_, _, _), _,
		_) :-
	% This should never happen
	error("Attempted base_typeclass_info unification").
unify_gen__generate_tag_test_rval_2(tabling_pointer_constant(_, _), _, _) :-
	% This should never happen
	error("Attempted tabling_pointer unification").
unify_gen__generate_tag_test_rval_2(deep_profiling_proc_layout_tag(_, _),
		_, _) :-
	% This should never happen
	error("Attempted deep_profiling_proc_layout_tag unification").
unify_gen__generate_tag_test_rval_2(table_io_decl_tag(_, _), _, _) :-
	% This should never happen
	error("Attempted table_io_decl_tag unification").
unify_gen__generate_tag_test_rval_2(no_tag, _Rval, TestRval) :-
	TestRval = const(true).
unify_gen__generate_tag_test_rval_2(single_functor, _Rval, TestRval) :-
	TestRval = const(true).
unify_gen__generate_tag_test_rval_2(unshared_tag(UnsharedTag), Rval,
		TestRval) :-
	VarPtag = unop(tag, Rval),
	ConstPtag = unop(mktag, const(int_const(UnsharedTag))),
	TestRval = binop(eq, VarPtag, ConstPtag).
unify_gen__generate_tag_test_rval_2(shared_remote_tag(Bits, Num), Rval,
		TestRval) :-
	VarPtag = unop(tag, Rval),
	ConstPtag = unop(mktag, const(int_const(Bits))),
	PtagTestRval = binop(eq, VarPtag, ConstPtag),
	VarStag = lval(field(yes(Bits), Rval, const(int_const(0)))),
	ConstStag = const(int_const(Num)),
	StagTestRval = binop(eq, VarStag, ConstStag),
	TestRval = binop(and, PtagTestRval, StagTestRval).
unify_gen__generate_tag_test_rval_2(shared_local_tag(Bits, Num), Rval,
		TestRval) :-
	ConstStag = mkword(Bits, unop(mkbody, const(int_const(Num)))),
	TestRval = binop(eq, Rval, ConstStag).
unify_gen__generate_tag_test_rval_2(reserved_address(RA), Rval, TestRval) :-
	TestRval = binop(eq, Rval, unify_gen__generate_reserved_address(RA)).
unify_gen__generate_tag_test_rval_2(
		shared_with_reserved_addresses(ReservedAddrs, ThisTag),
		Rval, FinalTestRval) :-
	%
	% We first check that the Rval doesn't match any of the
	% ReservedAddrs, and then check that it matches ThisTag.
	%
	CheckReservedAddrs = (func(RA, TestRval0) = TestRval :-
		unify_gen__generate_tag_test_rval_2(reserved_address(RA), Rval,
			EqualRA),
		TestRval = binop((and), unop(not, EqualRA), TestRval0)
	),
	unify_gen__generate_tag_test_rval_2(ThisTag, Rval, MatchesThisTag),
	FinalTestRval = list__foldr(CheckReservedAddrs, ReservedAddrs,
		MatchesThisTag).

:- func unify_gen__generate_reserved_address(reserved_address) = rval.

unify_gen__generate_reserved_address(null_pointer) = const(int_const(0)).
unify_gen__generate_reserved_address(small_pointer(N)) = const(int_const(N)).
unify_gen__generate_reserved_address(reserved_object(_, _, _)) = _ :-
	% These should only be used for the MLDS back-end
	unexpected(this_file, "reserved_object").

%---------------------------------------------------------------------------%

	% A construction unification is implemented as a simple assignment
	% of a function symbol if the function symbol has arity zero.
	% If the function symbol's arity is greater than zero, and all its
	% arguments are constants, the construction is implemented by
	% constructing the new term statically. If not all the argumemts are
	% constants, the construction is implemented as a heap-increment
	% to create a term, and a series of [optional] assignments to
	% instantiate the arguments of that term.

:- pred unify_gen__generate_construction(prog_var::in, cons_id::in,
	list(prog_var)::in, list(uni_mode)::in, maybe(term_size_value)::in,
	hlds_goal_info::in, code_tree::out, code_info::in, code_info::out)
	is det.

unify_gen__generate_construction(Var, Cons, Args, Modes, Size, GoalInfo,
		Code, !CI) :-
	Tag = code_info__cons_id_to_tag(!.CI, Var, Cons),
	unify_gen__generate_construction_2(Tag, Var, Args,
		Modes, Size, GoalInfo, Code, !CI).

:- pred unify_gen__generate_construction_2(cons_tag::in, prog_var::in,
	list(prog_var)::in, list(uni_mode)::in, maybe(term_size_value)::in,
	hlds_goal_info::in, code_tree::out, code_info::in, code_info::out)
	is det.

unify_gen__generate_construction_2(string_constant(String),
		Var, _Args, _Modes, _, _, empty, !CI) :-
	code_info__assign_const_to_var(Var, const(string_const(String)), !CI).
unify_gen__generate_construction_2(int_constant(Int),
		Var, _Args, _Modes, _, _, empty, !CI) :-
	code_info__assign_const_to_var(Var, const(int_const(Int)), !CI).
unify_gen__generate_construction_2(float_constant(Float),
		Var, _Args, _Modes, _, _, empty, !CI) :-
	code_info__assign_const_to_var(Var, const(float_const(Float)), !CI).
unify_gen__generate_construction_2(no_tag, Var, Args, Modes, _, _, Code,
		!CI) :-
	( Args = [Arg], Modes = [Mode] ->
		Type = code_info__variable_type(!.CI, Arg),
		unify_gen__generate_sub_unify(ref(Var), ref(Arg),
			Mode, Type, Code, !CI)
	;
		error("unify_gen__generate_construction_2: no_tag: " ++
			"arity != 1")
	).
unify_gen__generate_construction_2(single_functor,
		Var, Args, Modes, Size, GoalInfo, Code, !CI) :-
	% treat single_functor the same as unshared_tag(0)
	unify_gen__generate_construction_2(unshared_tag(0),
		Var, Args, Modes, Size, GoalInfo, Code, !CI).
unify_gen__generate_construction_2(unshared_tag(Ptag),
		Var, Args, Modes, Size, _, Code, !CI) :-
	code_info__get_module_info(!.CI, ModuleInfo),
	unify_gen__var_types(!.CI, Args, ArgTypes),
	unify_gen__generate_cons_args(Args, ArgTypes, Modes, ModuleInfo,
		Rvals),
	unify_gen__construct_cell(Var, Ptag, Rvals, Size, Code, !CI).
unify_gen__generate_construction_2(shared_remote_tag(Ptag, Sectag),
		Var, Args, Modes, Size, _, Code, !CI) :-
	code_info__get_module_info(!.CI, ModuleInfo),
	unify_gen__var_types(!.CI, Args, ArgTypes),
	unify_gen__generate_cons_args(Args, ArgTypes, Modes, ModuleInfo,
		Rvals0),
		% the first field holds the secondary tag
	Rvals = [yes(const(int_const(Sectag))) | Rvals0],
	unify_gen__construct_cell(Var, Ptag, Rvals, Size, Code, !CI).
unify_gen__generate_construction_2(shared_local_tag(Bits1, Num1),
		Var, _Args, _Modes, _, _, empty, !CI) :-
	code_info__assign_const_to_var(Var,
		mkword(Bits1, unop(mkbody, const(int_const(Num1)))), !CI).
unify_gen__generate_construction_2(type_ctor_info_constant(ModuleName,
		TypeName, TypeArity), Var, Args, _Modes, _, _, empty, !CI) :-
	( Args = [] ->
		true
	;
		error("unify_gen: type-info constant has args")
	),
	RttiTypeCtor = rtti_type_ctor(ModuleName, TypeName, TypeArity),
	DataAddr = rtti_addr(ctor_rtti_id(RttiTypeCtor, type_ctor_info)),
	code_info__assign_const_to_var(Var,
		const(data_addr_const(DataAddr, no)), !CI).
unify_gen__generate_construction_2(base_typeclass_info_constant(ModuleName,
		ClassId, Instance), Var, Args, _Modes, _, _, empty, !CI) :-
	( Args = [] ->
		true
	;
		error("unify_gen: typeclass-info constant has args")
	),
	TCName = generate_class_name(ClassId),
	code_info__assign_const_to_var(Var,
		const(data_addr_const(rtti_addr(tc_rtti_id(TCName,
			base_typeclass_info(ModuleName, Instance))),
			no)), !CI).
unify_gen__generate_construction_2(tabling_pointer_constant(PredId, ProcId),
		Var, Args, _Modes, _, _, empty, !CI) :-
	( Args = [] ->
		true
	;
		error("unify_gen: tabling pointer constant has args")
	),
	code_info__get_module_info(!.CI, ModuleInfo),
	ProcLabel = make_proc_label(ModuleInfo, PredId, ProcId),
	module_info_name(ModuleInfo, ModuleName),
	DataAddr = data_addr(ModuleName, tabling_pointer(ProcLabel)),
	code_info__assign_const_to_var(Var,
		const(data_addr_const(DataAddr, no)), !CI).
unify_gen__generate_construction_2(
		deep_profiling_proc_layout_tag(PredId, ProcId),
		Var, Args, _Modes, _, _, empty, !CI) :-
	( Args = [] ->
		true
	;
		error("unify_gen: deep_profiling_proc_static has args")
	),
	code_info__get_module_info(!.CI, ModuleInfo),
	RttiProcLabel = make_rtti_proc_label(ModuleInfo, PredId, ProcId),
	Origin = RttiProcLabel ^ pred_info_origin,
	( Origin = special_pred(_) ->
		UserOrUCI = uci
	;
		UserOrUCI = user
	),
	ProcKind = proc_layout_proc_id(UserOrUCI),
	DataAddr = layout_addr(proc_layout(RttiProcLabel, ProcKind)),
	code_info__assign_const_to_var(Var,
		const(data_addr_const(DataAddr, no)), !CI).
unify_gen__generate_construction_2(table_io_decl_tag(PredId, ProcId),
		Var, Args, _Modes, _, _, empty, !CI) :-
	( Args = [] ->
		true
	;
		error("unify_gen: table_io_decl has args")
	),
	code_info__get_module_info(!.CI, ModuleInfo),
	RttiProcLabel = make_rtti_proc_label(ModuleInfo, PredId, ProcId),
	DataAddr = layout_addr(table_io_decl(RttiProcLabel)),
	code_info__assign_const_to_var(Var,
		const(data_addr_const(DataAddr, no)), !CI).
unify_gen__generate_construction_2(reserved_address(RA),
		Var, Args, _Modes, _, _, empty, !CI) :-
	( Args = [] ->
		true
	;
		error("unify_gen: reserved_address constant has args")
	),
	code_info__assign_const_to_var(Var,
		unify_gen__generate_reserved_address(RA), !CI).
unify_gen__generate_construction_2(
		shared_with_reserved_addresses(_RAs, ThisTag),
		Var, Args, Modes, Size, GoalInfo, Code, !CI) :-
	% For shared_with_reserved_address, the sharing is only
	% important for tag tests, not for constructions,
	% so here we just recurse on the real representation.
	unify_gen__generate_construction_2(ThisTag,
		Var, Args, Modes, Size, GoalInfo, Code, !CI).
unify_gen__generate_construction_2(
		pred_closure_tag(PredId, ProcId, EvalMethod),
		Var, Args, _Modes, _, GoalInfo, Code, !CI) :-
	% This code constructs or extends a closure.
	% The structure of closures is defined in runtime/mercury_ho_call.h.

	code_info__get_module_info(!.CI, ModuleInfo),
	module_info_preds(ModuleInfo, Preds),
	map__lookup(Preds, PredId, PredInfo),
	pred_info_procedures(PredInfo, Procs),
	map__lookup(Procs, ProcId, ProcInfo),
%
% We handle currying of a higher-order pred variable as a special case.
% We recognize
%
%	P = l(P0, X, Y, Z)
%
% where
%
%	l(P0, A, B, C, ...) :- P0(A, B, C, ...).	% higher-order call
%
% as a special case, and generate special code to construct the
% new closure P from the old closure P0 by appending the args X, Y, Z.
% The advantage of this optimization is that when P is called, we
% will only need to do one indirect call rather than two.
% Its disadvantage is that the cost of creating the closure P is greater.
% Whether this is a net win depend on the number of times P is called.
%
% The pattern that this optimization looks for happens rarely at the moment.
% The reason is that although we allow the creation of closures with a simple
% syntax (e.g. P0 = append4([1])), we don't allow their extension with a
% similarly simple syntax (e.g. P = call(P0, [2])). In fact, typecheck.m
% contains code to detect such constructs, because it does not have code
% to typecheck them (you get a message about call/2 should be used as a goal,
% not an expression).
%
	proc_info_goal(ProcInfo, ProcInfoGoal),
	proc_info_interface_code_model(ProcInfo, CodeModel),
	proc_info_headvars(ProcInfo, ProcHeadVars),
	(
		EvalMethod = normal,
		Args = [CallPred | CallArgs],
		ProcHeadVars = [ProcPred | ProcArgs],
		ProcInfoGoal = generic_call(higher_order(ProcPred, _, _, _),
			ProcArgs, _, CallDeterminism) - _GoalInfo,
		determinism_to_code_model(CallDeterminism, CallCodeModel),
			% Check that the code models are compatible.
			% Note that det is not compatible with semidet,
			% and semidet is not compatible with nondet,
			% since the arguments go in different registers.
			% But det is compatible with nondet.
		( CodeModel = CallCodeModel
		; CodeModel = model_non, CallCodeModel = model_det
		),
			% This optimization distorts deep profiles, so don't
			% perform it in deep profiling grades.
		module_info_globals(ModuleInfo, Globals),
		globals__lookup_bool_option(Globals, profile_deep, Deep),
		Deep = no
	->
		( CallArgs = [] ->
			% if there are no new arguments, we can just use the
			% old closure
			code_info__assign_var_to_var(Var, CallPred, !CI),
			Code = empty
		;
			code_info__get_next_label(LoopStart, !CI),
			code_info__get_next_label(LoopTest, !CI),
			code_info__acquire_reg(r, LoopCounter, !CI),
			code_info__acquire_reg(r, NumOldArgs, !CI),
			code_info__acquire_reg(r, NewClosure, !CI),
			Zero = const(int_const(0)),
			One = const(int_const(1)),
			Two = const(int_const(2)),
			Three = const(int_const(3)),
			list__length(CallArgs, NumNewArgs),
			NumNewArgs_Rval = const(int_const(NumNewArgs)),
			NumNewArgsPlusThree = NumNewArgs + 3,
			NumNewArgsPlusThree_Rval =
				const(int_const(NumNewArgsPlusThree)),
			code_info__produce_variable(CallPred, OldClosureCode,
				OldClosure, !CI),
			NewClosureCode = node([
				comment("build new closure from old closure")
					- "",
				assign(NumOldArgs,
					lval(field(yes(0), OldClosure, Two)))
					- "get number of arguments",
				incr_hp(NewClosure, no, no,
					binop(+, lval(NumOldArgs),
					NumNewArgsPlusThree_Rval), "closure")
					- "allocate new closure",
				assign(field(yes(0), lval(NewClosure), Zero),
					lval(field(yes(0), OldClosure, Zero)))
					- "set closure layout structure",
				assign(field(yes(0), lval(NewClosure), One),
					lval(field(yes(0), OldClosure, One)))
					- "set closure code pointer",
				assign(field(yes(0), lval(NewClosure), Two),
					binop(+, lval(NumOldArgs),
						NumNewArgs_Rval))
					- "set new number of arguments",
				assign(NumOldArgs, binop(+, lval(NumOldArgs),
					Three))
					- "set up loop limit",
				assign(LoopCounter, Three)
					- "initialize loop counter",
				% It is possible for the number of hidden
				% arguments to be zero, in which case the body
				% of this loop should not be executed at all.
				% This is why we jump to the loop condition
				% test.
				goto(label(LoopTest))
					- ("enter the copy loop " ++
					"at the conceptual top"),
				label(LoopStart) - "start of loop",
				assign(field(yes(0), lval(NewClosure),
						lval(LoopCounter)),
					lval(field(yes(0), OldClosure,
						lval(LoopCounter))))
					- "copy old hidden argument",
				assign(LoopCounter,
					binop(+, lval(LoopCounter), One))
					- "increment loop counter",
				label(LoopTest)
					- ("do we have more old arguments " ++
					"to copy?"),
				if_val(binop(<, lval(LoopCounter),
					lval(NumOldArgs)),
					label(LoopStart))
					- "repeat the loop?"
			]),
			unify_gen__generate_extra_closure_args(CallArgs,
				LoopCounter, NewClosure, ExtraArgsCode, !CI),
			code_info__release_reg(LoopCounter, !CI),
			code_info__release_reg(NumOldArgs, !CI),
			code_info__release_reg(NewClosure, !CI),
			code_info__assign_lval_to_var(Var, NewClosure,
				AssignCode, !CI),
			Code =
				tree(OldClosureCode,
				tree(NewClosureCode,
				tree(ExtraArgsCode,
				     AssignCode)))
		)
	;
		CodeAddr = code_info__make_entry_label(!.CI, ModuleInfo,
			PredId, ProcId, no),
		code_util__extract_proc_label_from_code_addr(CodeAddr,
			ProcLabel),
		(
			EvalMethod = normal,
			CallArgsRval = const(code_addr_const(CodeAddr))
		;
			EvalMethod = (aditi_bottom_up),
			rl__get_c_interface_rl_proc_name(ModuleInfo,
				proc(PredId, ProcId), RLProcName),
			rl__proc_name_to_string(RLProcName, RLProcNameStr),
			InputTypes = list__map(code_info__variable_type(!.CI),
				Args),
			rl__schema_to_string(ModuleInfo,
				InputTypes, InputSchemaStr),
			AditiCallArgs = [
				const(string_const(RLProcNameStr)),
				const(string_const(InputSchemaStr))
			],
			code_info__add_static_cell_natural_types(AditiCallArgs,
				CallArgsDataAddr, !CI),
			CallArgsRval =
				const(data_addr_const(CallArgsDataAddr, no))
		),
		continuation_info__generate_closure_layout(
			ModuleInfo, PredId, ProcId, ClosureInfo),
		module_info_name(ModuleInfo, ModuleName),
		goal_info_get_context(GoalInfo, Context),
		term__context_file(Context, FileName),
		term__context_line(Context, LineNumber),
		goal_info_get_goal_path(GoalInfo, GoalPath),
		goal_path_to_string(GoalPath, GoalPathStr),
		code_info__get_cur_proc_label(!.CI, CallerProcLabel),
		code_info__get_next_closure_seq_no(SeqNo, !CI),
		code_info__get_static_cell_info(!.CI, StaticCellInfo0),
		stack_layout__construct_closure_layout(CallerProcLabel,
			SeqNo, ClosureInfo, ProcLabel, ModuleName,
			FileName, LineNumber, GoalPathStr,
			StaticCellInfo0, StaticCellInfo,
			ClosureLayoutRvalsTypes, Data),
		code_info__set_static_cell_info(StaticCellInfo, !CI),
		code_info__add_closure_layout(Data, !CI),
		% For now, closures always have zero size, and the size slot
		% is never looked at.
		code_info__add_static_cell(ClosureLayoutRvalsTypes,
			ClosureDataAddr, !CI),
		ClosureLayoutRval =
			const(data_addr_const(ClosureDataAddr, no)),
		list__length(Args, NumArgs),
		proc_info_arg_info(ProcInfo, ArgInfo),
		unify_gen__generate_pred_args(Args, ArgInfo, PredArgs),
		Vector = [
			yes(ClosureLayoutRval),
			yes(CallArgsRval),
			yes(const(int_const(NumArgs)))
			| PredArgs
		],
		code_info__assign_cell_to_var(Var, no, 0, Vector, no,
			"closure", Code, !CI)
	).

:- pred unify_gen__generate_extra_closure_args(list(prog_var)::in, lval::in,
	lval::in, code_tree::out, code_info::in, code_info::out) is det.

unify_gen__generate_extra_closure_args([], _, _, empty, !CI).
unify_gen__generate_extra_closure_args([Var | Vars], LoopCounter,
		NewClosure, Code, !CI) :-
	code_info__produce_variable(Var, Code0, Value, !CI),
	One = const(int_const(1)),
	Code1 = node([
		assign(field(yes(0), lval(NewClosure), lval(LoopCounter)),
			Value)
			- "set new argument field",
		assign(LoopCounter,
			binop(+, lval(LoopCounter), One))
			- "increment argument counter"
	]),
	Code = tree(tree(Code0, Code1), Code2),
	unify_gen__generate_extra_closure_args(Vars, LoopCounter,
		NewClosure, Code2, !CI).

:- pred unify_gen__generate_pred_args(list(prog_var)::in, list(arg_info)::in,
	list(maybe(rval))::out) is det.

unify_gen__generate_pred_args([], _, []).
unify_gen__generate_pred_args([_|_], [], _) :-
	error("unify_gen__generate_pred_args: insufficient args").
unify_gen__generate_pred_args([Var | Vars], [ArgInfo | ArgInfos],
		[Rval | Rvals]) :-
	ArgInfo = arg_info(_, ArgMode),
	( ArgMode = top_in ->
		Rval = yes(var(Var))
	;
		Rval = no
	),
	unify_gen__generate_pred_args(Vars, ArgInfos, Rvals).

:- pred unify_gen__generate_cons_args(list(prog_var)::in, list(type)::in,
	list(uni_mode)::in, module_info::in, list(maybe(rval))::out) is det.

unify_gen__generate_cons_args(Vars, Types, Modes, ModuleInfo, Args) :-
	(
		unify_gen__generate_cons_args_2(Vars, Types, Modes,
			ModuleInfo, Args0)
	->
		Args = Args0
	;
		error("unify_gen__generate_cons_args: length mismatch")
	).

	% Create a list of maybe(rval) for the arguments for a construction
	% unification. For each argument which is input to the construction
	% unification, we produce `yes(var(Var))', but if the argument is free,
	% we just produce `no', meaning don't generate an assignment to that
	% field.

:- pred unify_gen__generate_cons_args_2(list(prog_var)::in, list(type)::in,
	list(uni_mode)::in, module_info::in, list(maybe(rval))::out)
	is semidet.

unify_gen__generate_cons_args_2([], [], [], _, []).
unify_gen__generate_cons_args_2([Var | Vars], [Type | Types],
		[UniMode | UniModes], ModuleInfo, [Rval | RVals]) :-
	UniMode = ((_LI - RI) -> (_LF - RF)),
	( mode_to_arg_mode(ModuleInfo, (RI -> RF), Type, top_in) ->
		Rval = yes(var(Var))
	;
		Rval = no
	),
	unify_gen__generate_cons_args_2(Vars, Types, UniModes, ModuleInfo,
		RVals).

:- pred unify_gen__construct_cell(prog_var::in, tag::in, list(maybe(rval))::in,
	maybe(term_size_value)::in, code_tree::out,
	code_info::in, code_info::out) is det.

unify_gen__construct_cell(Var, Ptag, Rvals, Size, Code, !CI) :-
	VarType = code_info__variable_type(!.CI, Var),
	unify_gen__var_type_msg(VarType, VarTypeMsg),
	% If we're doing accurate GC, then for types which hold RTTI that
	% will be traversed by the collector at GC-time, we need to allocate
	% an extra word at the start, to hold the forwarding pointer.
	% Normally we would just overwrite the first word of the object
	% in the "from" space, but this can't be done for objects which will be
	% referenced during the garbage collection process.
	(
		code_info__get_globals(!.CI, Globals),
		globals__get_gc_method(Globals, GCMethod),
		GCMethod = accurate,
		is_introduced_type_info_type(VarType)
	->
		ReserveWordAtStart = yes
	;
		ReserveWordAtStart = no
	),
	code_info__assign_cell_to_var(Var, ReserveWordAtStart, Ptag, Rvals,
		Size, VarTypeMsg, Code, !CI).

%---------------------------------------------------------------------------%

:- pred unify_gen__var_types(code_info::in, list(prog_var)::in,
	list(type)::out) is det.

unify_gen__var_types(CI, Vars, Types) :-
	code_info__get_proc_info(CI, ProcInfo),
	proc_info_vartypes(ProcInfo, VarTypes),
	map__apply_to_list(Vars, VarTypes, Types).

%---------------------------------------------------------------------------%

	% Construct a pair of lists that associates the fields of
	% a term with variables.

:- pred unify_gen__make_fields_and_argvars(list(prog_var)::in, rval::in,
	int::in, int::in, list(uni_val)::out, list(uni_val)::out) is det.

unify_gen__make_fields_and_argvars([], _, _, _, [], []).
unify_gen__make_fields_and_argvars([Var | Vars], Rval, Field0, TagNum,
		[F | Fs], [A | As]) :-
	F = lval(field(yes(TagNum), Rval, const(int_const(Field0)))),
	A = ref(Var),
	Field1 = Field0 + 1,
	unify_gen__make_fields_and_argvars(Vars, Rval, Field1, TagNum, Fs, As).

%---------------------------------------------------------------------------%

	% Generate a deterministic deconstruction. In a deterministic
	% deconstruction, we know the value of the tag, so we don't
	% need to generate a test.

	% Deconstructions are generated semi-eagerly. Any test sub-
	% unifications are generated eagerly (they _must_ be), but
	% assignment unifications are cached.

:- pred unify_gen__generate_det_deconstruction(prog_var::in, cons_id::in,
	list(prog_var)::in, list(uni_mode)::in, code_tree::out,
	code_info::in, code_info::out) is det.

unify_gen__generate_det_deconstruction(Var, Cons, Args, Modes, Code, !CI) :-
	Tag = code_info__cons_id_to_tag(!.CI, Var, Cons),
	unify_gen__generate_det_deconstruction_2(Var, Cons, Args, Modes,
		Tag, Code, !CI).

:- pred unify_gen__generate_det_deconstruction_2(prog_var::in, cons_id::in,
	list(prog_var)::in, list(uni_mode)::in, cons_tag::in,
	code_tree::out, code_info::in, code_info::out) is det.

unify_gen__generate_det_deconstruction_2(Var, Cons, Args, Modes, Tag, Code,
		!CI) :-
	% For constants, if the deconstruction is det, then we already know
	% the value of the constant, so Code = empty.
	(
		Tag = string_constant(_String),
		Code = empty
	;
		Tag = int_constant(_Int),
		Code = empty
	;
		Tag = float_constant(_Float),
		Code = empty
	;
		Tag = pred_closure_tag(_, _, _),
		Code = empty
	;
		Tag = type_ctor_info_constant(_, _, _),
		Code = empty
	;
		Tag = base_typeclass_info_constant(_, _, _),
		Code = empty
	;
		Tag = tabling_pointer_constant(_, _),
		Code = empty
	;
		Tag = deep_profiling_proc_layout_tag(_, _),
		Code = empty
	;
		Tag = table_io_decl_tag(_, _),
		error("unify_gen__generate_det_deconstruction: " ++
			"table_io_decl_tag")
	;
		Tag = no_tag,
		( Args = [Arg], Modes = [Mode] ->
			VarType = code_info__variable_type(!.CI, Var),
			( is_dummy_argument_type(VarType) ->
				% We must handle this case specially. If we
				% didn't, the generated code would copy the
				% reference to the Var's current location,
				% which may be stackvar(N) or framevar(N) for
				% negative N, to be the location of Arg, and
				% since Arg may not be a dummy type, it would
				% actually use that location. This can happen
				% in the unify/compare routines for e.g.
				% io__state.

				( variable_is_forward_live(!.CI, Arg) ->
					code_info__assign_const_to_var(Arg,
						const(int_const(0)), !CI)
				;
					true
				),
				Code = empty
			;
				ArgType = code_info__variable_type(!.CI, Arg),
				unify_gen__generate_sub_unify(ref(Var),
					ref(Arg), Mode, ArgType, Code, !CI)
			)
		;
			error("unify_gen__generate_det_deconstruction: " ++
				"no_tag: arity != 1")
		)
	;
		Tag = single_functor,
		% treat single_functor the same as unshared_tag(0)
		unify_gen__generate_det_deconstruction_2(Var, Cons, Args,
			Modes, unshared_tag(0), Code, !CI)
	;
		Tag = unshared_tag(Ptag),
		Rval = var(Var),
		unify_gen__make_fields_and_argvars(Args, Rval, 0,
			Ptag, Fields, ArgVars),
		unify_gen__var_types(!.CI, Args, ArgTypes),
		unify_gen__generate_unify_args(Fields, ArgVars,
			Modes, ArgTypes, Code, !CI)
	;
		Tag = shared_remote_tag(Ptag, _Sectag1),
		Rval = var(Var),
		unify_gen__make_fields_and_argvars(Args, Rval, 1,
			Ptag, Fields, ArgVars),
		unify_gen__var_types(!.CI, Args, ArgTypes),
		unify_gen__generate_unify_args(Fields, ArgVars,
			Modes, ArgTypes, Code, !CI)
	;
		Tag = shared_local_tag(_Ptag, _Sectag2),
		Code = empty % if this is det, then nothing happens
	;
		Tag = reserved_address(_RA),
		Code = empty % if this is det, then nothing happens
	;
		% For shared_with_reserved_address, the sharing is only
		% important for tag tests, not for det deconstructions,
		% so here we just recurse on the real representation.
		Tag = shared_with_reserved_addresses(_RAs, ThisTag),
		unify_gen__generate_det_deconstruction_2(Var, Cons, Args,
			Modes, ThisTag, Code, !CI)
	).

%---------------------------------------------------------------------------%

	% Generate a semideterministic deconstruction.
	% A semideterministic deconstruction unification is tag-test
	% followed by a deterministic deconstruction.

:- pred unify_gen__generate_semi_deconstruction(prog_var::in, cons_id::in,
	list(prog_var)::in, list(uni_mode)::in,
	code_tree::out, code_info::in, code_info::out) is det.

unify_gen__generate_semi_deconstruction(Var, Tag, Args, Modes, Code, !CI) :-
	unify_gen__generate_tag_test(Var, Tag, branch_on_success,
		SuccLab, TagTestCode, !CI),
	code_info__remember_position(!.CI, AfterUnify),
	code_info__generate_failure(FailCode, !CI),
	code_info__reset_to_position(AfterUnify, !CI),
	unify_gen__generate_det_deconstruction(Var, Tag, Args, Modes,
		DeconsCode, !CI),
	SuccessLabelCode = node([
		label(SuccLab) - ""
	]),
	Code =
		tree(TagTestCode,
		tree(FailCode,
		tree(SuccessLabelCode,
		     DeconsCode))).

%---------------------------------------------------------------------------%

	% Generate code to perform a list of deterministic subunifications
	% for the arguments of a construction.

:- pred unify_gen__generate_unify_args(list(uni_val)::in, list(uni_val)::in,
	list(uni_mode)::in, list(type)::in, code_tree::out,
	code_info::in, code_info::out) is det.

unify_gen__generate_unify_args(Ls, Rs, Ms, Ts, Code, !CI) :-
	( unify_gen__generate_unify_args_2(Ls, Rs, Ms, Ts, Code0, !CI) ->
		Code = Code0
	;
		error("unify_gen__generate_unify_args: length mismatch")
	).

:- pred unify_gen__generate_unify_args_2(list(uni_val)::in, list(uni_val)::in,
	list(uni_mode)::in, list(type)::in, code_tree::out,
	code_info::in, code_info::out) is semidet.

unify_gen__generate_unify_args_2([], [], [], [], empty, !CI).
unify_gen__generate_unify_args_2([L | Ls], [R | Rs], [M | Ms], [T | Ts],
		Code, !CI) :-
	unify_gen__generate_sub_unify(L, R, M, T, CodeA, !CI),
	unify_gen__generate_unify_args_2(Ls, Rs, Ms, Ts, CodeB, !CI),
	Code = tree(CodeA, CodeB).

%---------------------------------------------------------------------------%

	% Generate a subunification between two [field|variable].

:- pred unify_gen__generate_sub_unify(uni_val::in, uni_val::in, uni_mode::in,
	(type)::in, code_tree::out, code_info::in, code_info::out) is det.

unify_gen__generate_sub_unify(L, R, Mode, Type, Code, !CI) :-
	Mode = ((LI - RI) -> (LF - RF)),
	code_info__get_module_info(!.CI, ModuleInfo),
	mode_to_arg_mode(ModuleInfo, (LI -> LF), Type, LeftMode),
	mode_to_arg_mode(ModuleInfo, (RI -> RF), Type, RightMode),
	(
			% Input - input == test unification
		LeftMode = top_in,
		RightMode = top_in
	->
		% This shouldn't happen, since mode analysis should
		% avoid creating any tests in the arguments
		% of a construction or deconstruction unification.
		error("test in arg of [de]construction")
	;
			% Input - Output== assignment ->
		LeftMode = top_in,
		RightMode = top_out
	->
		unify_gen__generate_sub_assign(R, L, Code, !CI)
	;
			% Output - Input== assignment <-
		LeftMode = top_out,
		RightMode = top_in
	->
		unify_gen__generate_sub_assign(L, R, Code, !CI)
	;
		LeftMode = top_unused,
		RightMode = top_unused
	->
		Code = empty % free-free - ignore
			% XXX I think this will have to change
			% if we start to support aliasing
	;
		error("unify_gen__generate_sub_unify: some strange unify")
	).

%---------------------------------------------------------------------------%

:- pred unify_gen__generate_sub_assign(uni_val::in, uni_val::in,
	code_tree::out, code_info::in, code_info::out) is det.

	% Assignment between two lvalues - cannot happen.
unify_gen__generate_sub_assign(lval(_Lval0), lval(_Rval), _Code, !CI) :-
	error("unify_gen__generate_sub_assign: lval/lval").

	% Assignment from a variable to an lvalue - cannot cache
	% so generate immediately.
unify_gen__generate_sub_assign(lval(Lval0), ref(Var), Code, !CI) :-
	code_info__produce_variable(Var, SourceCode, Source, !CI),
	code_info__materialize_vars_in_rval(lval(Lval0), NewLval,
		MaterializeCode, !CI),
	( NewLval = lval(Lval) ->
		Code = tree(
			tree(SourceCode, MaterializeCode),
			node([
				assign(Lval, Source) - "Copy value"
			])
		)
	;
		error("unify_gen__generate_sub_assign: " ++
			"lval vanished with ref")
	).
	% Assignment to a variable, so cache it.
unify_gen__generate_sub_assign(ref(Var), lval(Lval), Code, !CI) :-
	( code_info__variable_is_forward_live(!.CI, Var) ->
		code_info__assign_lval_to_var(Var, Lval, Code, !CI)
	;
		Code = empty
	).
	% Assignment to a variable, so cache it.
unify_gen__generate_sub_assign(ref(Lvar), ref(Rvar), empty, !CI) :-
	( code_info__variable_is_forward_live(!.CI, Lvar) ->
		code_info__assign_var_to_var(Lvar, Rvar, !CI)
	;
		true
	).

%---------------------------------------------------------------------------%

:- pred unify_gen__var_type_msg((type)::in, string::out) is det.

unify_gen__var_type_msg(Type, Msg) :-
	( type_to_ctor_and_args(Type, TypeCtor, _) ->
		TypeCtor = TypeSym - TypeArity,
		mdbcomp__prim_data__sym_name_to_string(TypeSym, TypeSymStr),
		string__int_to_string(TypeArity, TypeArityStr),
		string__append_list([TypeSymStr, "/", TypeArityStr], Msg)
	;
		error("type is still a type variable in var_type_msg")
	).

%---------------------------------------------------------------------------%

:- func this_file = string.

this_file = "unify_gen.m".

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%
