%-----------------------------------------------------------------------------%
% Copyright (C) 1997-2005 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Author: zs.
%
% This module handles the generation of traces for the trace analysis system.
%
% For the general basis of trace analysis systems, see the paper
% "Opium: An extendable trace analyser for Prolog" by Mireille Ducasse,
% available from http://www.irisa.fr/lande/ducasse.
%
% We reserve some slots in the stack frame of the traced procedure.
% One contains the call sequence number, which is set in the procedure prologue
% by incrementing a global counter. Another contains the call depth, which
% is also set by incrementing a global variable containing the depth of the
% caller. The caller sets this global variable from its own saved depth
% just before the call. We also save the event number, and sometimes also
% the redo layout and the from_full flag.
%
% Each event has a label associated with it. The stack layout for that label
% records what variables are live and where they are at the time of the event.
% These labels are generated by the same predicate that generates the code
% for the event, and are initially not used for anything else.
% However, some of these labels may be fallen into from other places,
% and thus optimization may redirect references from labels to one of these
% labels. This cannot happen in the opposite direction, due to the reference
% to each event's label from the event's pragma C code instruction.
% (This prevents labelopt from removing the label.)
%
% We classify events into three kinds: external events (call, exit, fail),
% internal events (switch, disj, ite_then, ite_else), and nondet pragma C
% events (first, later). Code_gen.m, which calls this module to generate
% all external events, checks whether tracing is required before calling us;
% the predicates handing internal and nondet pragma C events must check this
% themselves. The predicates generating internal events need the goal
% following the event as a parameter. For the first and later arms of
% nondet pragma C code, there is no such hlds_goal, which is why these events
% need a bit of special treatment.

%-----------------------------------------------------------------------------%

:- module ll_backend__trace.

:- interface.

:- import_module hlds__hlds_goal.
:- import_module hlds__hlds_module.
:- import_module hlds__hlds_pred.
:- import_module libs__globals.
:- import_module ll_backend__code_info.
:- import_module ll_backend__llds.
:- import_module parse_tree__prog_data.

:- import_module map.
:- import_module set.
:- import_module std_util.

	% The kinds of external ports for which the code we generate will
	% call MR_trace. The redo port is not on this list, because for that
	% port the code that calls MR_trace is not in compiler-generated code,
	% but in the runtime system.  Likewise for the exception port.
	% (The same comment applies to the type `trace_port' in llds.m.)
:- type external_trace_port
	--->	call
	;	exit
	;	fail.

	% These ports are different from other internal ports (even neg_enter)
	% because their goal path identifies not the goal we are about to enter
	% but the goal we have just left.
:- type negation_end_port
	--->	neg_success
	;	neg_failure.

:- type nondet_pragma_trace_port
	--->	nondet_pragma_first
	;	nondet_pragma_later.

:- type trace_info.

:- type trace_slot_info --->
	trace_slot_info(
		slot_from_full		:: maybe(int),
					% If the procedure is shallow traced,
					% this will be yes(N), where stack
					% slot N is the slot that holds the
					% value of the from-full flag at call.
					% Otherwise, it will be no.

		slot_io			:: maybe(int),
					% If the procedure has io state
					% arguments this will be yes(N), where
					% stack slot N is the slot that holds
					% the saved value of the io sequence
					% number. Otherwise, it will be no.

		slot_trail		:: maybe(int),
					% If --use-trail is set, this will
					% be yes(M), where stack slots M
					% and M+1 are the slots that hold the
					% saved values of the trail pointer
					% and the ticket counter respectively
					% at the time of the call. Otherwise,
					% it will be no.

		slot_maxfr		:: maybe(int),
					% If the procedure lives on the det
					% stack but creates temporary frames
					% on the nondet stack, this will be
					% yes(M), where stack slot M is
					% reserved to hold the value of maxfr
					% at the time of the call. Otherwise,
					% it will be no.

		slot_call_table		:: maybe(int)
					% If the procedure's evaluation method
					% is memo, loopcheck or minimal model,
					% this will be yes(M), where stack slot
					% M holds the variable that represents
					% the tip of the call table. Otherwise,
					% it will be no.
	).

	% Return the set of input variables whose values should be preserved
	% until the exit and fail ports. This will be all the input variables,
	% except those that can be totally clobbered during the evaluation
	% of the procedure (those partially clobbered may still be of interest,
	% although to handle them properly we need to record insts in stack
	% layouts), and those of dummy types.
:- pred trace__fail_vars(module_info::in, proc_info::in,
	set(prog_var)::out) is det.

	% Figure out whether we need a slot for storing the value of maxfr
	% on entry, and record the result in the proc info.
:- pred trace__do_we_need_maxfr_slot(globals::in, pred_info::in, proc_info::in,
	proc_info::out) is det.

	% Return the number of slots reserved for tracing information.
	% If there are N slots, the reserved slots will be 1 through N.
	%
	% It is possible that one of these reserved slots contains a variable.
	% If so, the variable and its slot number are returned in the last
	% argument.
:- pred trace__reserved_slots(module_info::in, pred_info::in, proc_info::in,
	globals::in, int::out, maybe(pair(prog_var, int))::out) is det.

	% Construct and return an abstract struct that represents the
	% tracing-specific part of the code generator state. Return also
	% info about the non-fixed slots used by the tracing system,
	% for eventual use in the constructing the procedure's layout
	% structure.
:- pred trace__setup(module_info::in, pred_info::in, proc_info::in,
	globals::in, trace_slot_info::out, trace_info::out,
	code_info::in, code_info::out) is det.

	% Generate code to fill in the reserved stack slots.
:- pred trace__generate_slot_fill_code(code_info::in, trace_info::in,
	code_tree::out) is det.

	% If we are doing execution tracing, generate code to prepare for
	% a call.
:- pred trace__prepare_for_call(code_info::in, code_tree::out) is det.

	% If we are doing execution tracing, generate code for an internal
	% trace event. This predicate must be called just before generating
	% code for the given goal.
:- pred trace__maybe_generate_internal_event_code(hlds_goal::in,
	hlds_goal_info::in, code_tree::out, code_info::in, code_info::out)
	is det.

	% If we are doing execution tracing, generate code for an trace event
	% that represents leaving a negated goal (via success or failure).
:- pred trace__maybe_generate_negated_event_code(hlds_goal::in,
	hlds_goal_info::in, negation_end_port::in, code_tree::out,
	code_info::in, code_info::out) is det.

	% If we are doing execution tracing, generate code for a nondet
	% pragma C code trace event.
:- pred trace__maybe_generate_pragma_event_code(nondet_pragma_trace_port::in,
	prog_context::in, code_tree::out, code_info::in, code_info::out)
	is det.

:- type external_event_info
	--->	external_event_info(
			label,		% The label associated with the
					% external event.
			map(tvar, set(layout_locn)),
					% The map saying where the typeinfo
					% variables needed to describe the
					% types of the variables live at the
					% event are.
			code_tree	% The code generated for the event.
		).

	% Generate code for an external trace event.
	% Besides the trace code, we return the label on which we have hung
	% the trace liveness information and data on the type variables in the
	% liveness information, since some of our callers also need this
	% information.
:- pred trace__generate_external_event_code(external_trace_port::in,
	trace_info::in, prog_context::in, maybe(external_event_info)::out,
	code_info::in, code_info::out) is det.

	% If the trace level calls for redo events, generate code that pushes
	% a temporary nondet stack frame whose redoip slot contains the
	% address of one of the labels in the runtime that calls MR_trace
	% for a redo event. Otherwise, generate empty code.
:- pred trace__maybe_setup_redo_event(trace_info::in, code_tree::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module check_hlds__inst_match.
:- import_module check_hlds__mode_util.
:- import_module check_hlds__type_util.
:- import_module hlds__code_model.
:- import_module hlds__hlds_llds.
:- import_module hlds__instmap.
:- import_module libs__options.
:- import_module libs__trace_params.
:- import_module libs__tree.
:- import_module ll_backend__code_util.
:- import_module ll_backend__continuation_info.
:- import_module ll_backend__layout_out.
:- import_module ll_backend__llds_out.
:- import_module mdbcomp__prim_data.

:- import_module bool.
:- import_module int.
:- import_module list.
:- import_module map.
:- import_module require.
:- import_module std_util.
:- import_module string.
:- import_module term.
:- import_module varset.

	% Information specific to a trace port.
:- type trace_port_info
	--->	external
	;	internal(
			goal_path,	% The path of the goal whose start
					% this port represents.
			set(prog_var)	% The pre-death set of this goal.
		)
	;	negation_end(
			goal_path	% The path of the goal whose end
					% (one way or another) this port
					% represents.
		)
	;	nondet_pragma.

trace__fail_vars(ModuleInfo, ProcInfo, FailVars) :-
	proc_info_headvars(ProcInfo, HeadVars),
	proc_info_argmodes(ProcInfo, Modes),
	proc_info_arg_info(ProcInfo, ArgInfos),
	proc_info_vartypes(ProcInfo, VarTypes),
	mode_list_get_final_insts(Modes, ModuleInfo, Insts),
	(
		trace__build_fail_vars(HeadVars, Insts, ArgInfos,
			ModuleInfo, VarTypes, FailVarsList)
	->
		set__list_to_set(FailVarsList, FailVars)
	;
		error("length mismatch in trace__fail_vars")
	).

trace__do_we_need_maxfr_slot(Globals, PredInfo0, !ProcInfo) :-
	globals__get_trace_level(Globals, TraceLevel),
	proc_info_interface_code_model(!.ProcInfo, CodeModel),
	(
		eff_trace_level_is_none(PredInfo0, !.ProcInfo, TraceLevel)
			= no,
		CodeModel \= model_non,
		proc_info_goal(!.ProcInfo, Goal),
		code_util__goal_may_alloc_temp_frame(Goal)
	->
		MaxfrFlag = yes
	;
		MaxfrFlag = no
	),
	proc_info_set_need_maxfr_slot(MaxfrFlag, !ProcInfo).

	% trace__reserved_slots and trace__setup cooperate in the allocation
	% of stack slots for tracing purposes. The allocation is done in the
	% following stages.
	%
	% stage 1:	Allocate the fixed slots, slots 1, 2 and 3, to hold
	%		the event number of call, the call sequence number
	%		and the call depth respectively.
	%
	% stage 2:	If the procedure is model_non and --trace-redo is set,
	%		allocate the next available slot (which must be slot 4)
	%		to hold the address of the redo layout structure.
	%
	% stage 3:	If the procedure is shallow traced, allocate the
	%		next available slot to the saved copy of the
	%		from-full flag. The number of this slot is recorded
	%		in the maybe_from_full field in the proc layout;
	%		if there is no such slot, that field will contain -1.
	%
	% stage 4:	If --trace-table-io is given, allocate the next slot
	%		to hold the saved value of the io sequence number,
	%		for use in implementing retry. The number of this slot
	%		is recorded in the maybe_io_seq field in the proc
	%		layout; if there is no such slot, that field will
	%		contain -1.
	%
	% stage 5:	If --use-trail is set (given or implied), allocate
	%		two slots to hold the saved value of the trail pointer
	%		and the ticket counter at the point of the call, for
	%		use in implementing retry. The number of the first of
	%		these two slots is recorded in the maybe_trail field
	%		in the proc layout; if there are no such slots, that
	%		field will contain -1.
	%
	% stage 6:	If the procedure lives on the det stack but can put
	%		frames on the nondet stack, allocate a slot to hold
	%		the saved value of maxfr at the point of the call,
	%		for use in implementing retry. The number of this
	%		slot is recorded in the maybe_maxfr field in the proc
	%		layout; if there is no such slot, that field will
	%		contain -1.
	%
	% stage 7:	If the procedure's evaluation method is memo, loopcheck
	%		or minimal model, we allocate a slot to hold the
	%		variable that represents the tip of the call table.
	%		The debugger needs this, because when it executes a
	%		retry command, it must reset this tip to uninitialized.
	%		The number of this slot is recorded in the maybe_table
	%		field in the proc layout; if there is no such slot,
	%		that field will contain -1.
	%
	% The procedure's layout structure does not need to include
	% information about the presence or absence of the slot holding
	% the address of the redo layout structure. If we generate redo
	% trace events, the runtime will know that this slot exists and
	% what its number must be; if we do not, the runtime will never
	% refer to such a slot.
	%
	% We need two redo labels in the runtime. Deep traced procedures
	% do not have a from-full slot, but their slots 1 through 4 are always
	% valid; the label handling their redos accesses those slots directly.
	% Shallow traced procedures do have a from-full slot, and their slots
	% 1-4 are valid only if the from-full slot is MR_TRUE; the label
	% handling their redos thus checks this slot to see whether it can
	% (or should) access the other slots. In shallow-traced model_non
	% procedures that generate redo events, the from-full flag is always
	% in slot 5.
	%
	% The slots allocated by stages 1 and 2 are only ever referred to
	% by the runtime system if they are guaranteed to exist. The runtime
	% system may of course also need to refer to slots allocated by later
	% stages, but before it does so, it needs to know whether those slots
	% exist or not. This is why trace__setup returns TraceSlotInfo,
	% which answers such questions, for later inclusion in the
	% procedure's layout structure.

trace__reserved_slots(_ModuleInfo, PredInfo, ProcInfo, Globals, ReservedSlots,
		MaybeTableVarInfo) :-
	globals__get_trace_level(Globals, TraceLevel),
	globals__get_trace_suppress(Globals, TraceSuppress),
	globals__lookup_bool_option(Globals, trace_table_io, TraceTableIo),
	FixedSlots = eff_trace_level_needs_fixed_slots(PredInfo, ProcInfo,
		TraceLevel),
	(
		FixedSlots = no,
		ReservedSlots = 0,
		MaybeTableVarInfo = no
	;
		FixedSlots = yes,
		Fixed = 3, % event#, call#, call depth
		(
			proc_info_interface_code_model(ProcInfo, model_non),
			eff_trace_needs_port(PredInfo, ProcInfo, TraceLevel,
				TraceSuppress, redo) = yes
		->
			RedoLayout = 1
		;
			RedoLayout = 0
		),
		(
			eff_trace_level_needs_from_full_slot(PredInfo,
				ProcInfo, TraceLevel) = yes
		->
			FromFull = 1
		;
			FromFull = 0
		),
		( TraceTableIo = yes ->
			IoSeq = 1
		;
			IoSeq = 0
		),
		globals__lookup_bool_option(Globals, use_trail, UseTrail),
		( UseTrail = yes ->
			Trail = 2
		;
			Trail = 0
		),
		proc_info_get_need_maxfr_slot(ProcInfo, NeedMaxfr),
		(
			NeedMaxfr = yes,
			Maxfr = 1
		;
			NeedMaxfr = no,
			Maxfr = 0
		),
		ReservedSlots0 = Fixed + RedoLayout + FromFull + IoSeq
			+ Trail + Maxfr,
		proc_info_get_call_table_tip(ProcInfo, MaybeCallTableVar),
		( MaybeCallTableVar = yes(CallTableVar) ->
			ReservedSlots = ReservedSlots0 + 1,
			MaybeTableVarInfo = yes(CallTableVar - ReservedSlots)
		;
			ReservedSlots = ReservedSlots0,
			MaybeTableVarInfo = no
		)
	).

trace__setup(_ModuleInfo, PredInfo, ProcInfo, Globals, TraceSlotInfo,
		TraceInfo, !CI) :-
	CodeModel = code_info__get_proc_model(!.CI),
	globals__get_trace_level(Globals, TraceLevel),
	globals__get_trace_suppress(Globals, TraceSuppress),
	globals__lookup_bool_option(Globals, trace_table_io, TraceTableIo),
	TraceRedo = eff_trace_needs_port(PredInfo, ProcInfo, TraceLevel,
		TraceSuppress, redo),
	(
		TraceRedo = yes,
		CodeModel = model_non
	->
		code_info__get_next_label(RedoLayoutLabel, !CI),
		MaybeRedoLayoutLabel = yes(RedoLayoutLabel),
		NextSlotAfterRedoLayout = 5
	;
		MaybeRedoLayoutLabel = no,
		NextSlotAfterRedoLayout = 4
	),
	FromFullSlot = eff_trace_level_needs_from_full_slot(PredInfo,
		ProcInfo, TraceLevel),
	(
		FromFullSlot = no,
		MaybeFromFullSlot = no,
		MaybeFromFullSlotLval = no,
		NextSlotAfterFromFull = NextSlotAfterRedoLayout
	;
		FromFullSlot = yes,
		MaybeFromFullSlot = yes(NextSlotAfterRedoLayout),
		CallFromFullSlot = llds__stack_slot_num_to_lval(
			CodeModel, NextSlotAfterRedoLayout),
		MaybeFromFullSlotLval = yes(CallFromFullSlot),
		NextSlotAfterFromFull = NextSlotAfterRedoLayout + 1
	),
	(
		TraceTableIo = yes,
		MaybeIoSeqSlot = yes(NextSlotAfterFromFull),
		IoSeqLval = llds__stack_slot_num_to_lval(CodeModel,
			NextSlotAfterFromFull),
		MaybeIoSeqLval = yes(IoSeqLval),
		NextSlotAfterIoSeq = NextSlotAfterFromFull + 1
	;
		TraceTableIo = no,
		MaybeIoSeqSlot = no,
		MaybeIoSeqLval = no,
		NextSlotAfterIoSeq = NextSlotAfterFromFull
	),
	( globals__lookup_bool_option(Globals, use_trail, yes) ->
		MaybeTrailSlot = yes(NextSlotAfterIoSeq),
		TrailLval = llds__stack_slot_num_to_lval(CodeModel,
			NextSlotAfterIoSeq),
		TicketLval = llds__stack_slot_num_to_lval(CodeModel,
			NextSlotAfterIoSeq + 1),
		MaybeTrailLvals = yes(TrailLval - TicketLval),
		NextSlotAfterTrail = NextSlotAfterIoSeq + 2
	;
		MaybeTrailSlot = no,
		MaybeTrailLvals = no,
		NextSlotAfterTrail = NextSlotAfterIoSeq
	),
	proc_info_get_need_maxfr_slot(ProcInfo, NeedMaxfr),
	(
		NeedMaxfr = yes,
		MaybeMaxfrSlot = yes(NextSlotAfterTrail),
		MaxfrLval = llds__stack_slot_num_to_lval(CodeModel,
			NextSlotAfterTrail),
		MaybeMaxfrLval = yes(MaxfrLval),
		NextSlotAfterMaxfr = NextSlotAfterTrail + 1
	;
		NeedMaxfr = no,
		MaybeMaxfrSlot = no,
		MaybeMaxfrLval = no,
		NextSlotAfterMaxfr = NextSlotAfterTrail
	),
	( proc_info_get_call_table_tip(ProcInfo, yes(_)) ->
		MaybeCallTableSlot = yes(NextSlotAfterMaxfr),
		CallTableLval = llds__stack_slot_num_to_lval(CodeModel,
			NextSlotAfterMaxfr),
		MaybeCallTableLval = yes(CallTableLval)
	;
		MaybeCallTableSlot = no,
		MaybeCallTableLval = no
	),
	TraceSlotInfo = trace_slot_info(MaybeFromFullSlot, MaybeIoSeqSlot,
		MaybeTrailSlot, MaybeMaxfrSlot, MaybeCallTableSlot),
	TraceInfo = trace_info(TraceLevel, TraceSuppress,
		MaybeFromFullSlotLval, MaybeIoSeqLval, MaybeTrailLvals,
		MaybeMaxfrLval, MaybeCallTableLval, MaybeRedoLayoutLabel).

trace__generate_slot_fill_code(CI, TraceInfo, TraceCode) :-
	CodeModel = code_info__get_proc_model(CI),
	MaybeFromFullSlot  = TraceInfo ^ from_full_lval,
	MaybeIoSeqSlot     = TraceInfo ^ io_seq_lval,
	MaybeTrailLvals    = TraceInfo ^ trail_lvals,
	MaybeMaxfrLval     = TraceInfo ^ maxfr_lval,
	MaybeCallTableLval = TraceInfo ^ call_table_tip_lval,
	MaybeRedoLabel     = TraceInfo ^ redo_label,
	trace__event_num_slot(CodeModel, EventNumLval),
	trace__call_num_slot(CodeModel, CallNumLval),
	trace__call_depth_slot(CodeModel, CallDepthLval),
	trace__stackref_to_string(EventNumLval, EventNumStr),
	trace__stackref_to_string(CallNumLval, CallNumStr),
	trace__stackref_to_string(CallDepthLval, CallDepthStr),
	string__append_list(["\t\tMR_trace_fill_std_slots(",
		EventNumStr, ", ", CallNumStr, ", ", CallDepthStr, ");\n"
	], FillThreeSlots),
	(
		MaybeIoSeqSlot = yes(IoSeqLval),
		trace__stackref_to_string(IoSeqLval, IoSeqStr),
		string__append_list([
			FillThreeSlots,
			"\t\t", IoSeqStr, " = MR_io_tabling_counter;\n"
		], FillSlotsUptoIoSeq)
	;
		MaybeIoSeqSlot = no,
		FillSlotsUptoIoSeq = FillThreeSlots
	),
	(
		MaybeRedoLabel = yes(RedoLayoutLabel),
		trace__redo_layout_slot(CodeModel, RedoLayoutLval),
		trace__stackref_to_string(RedoLayoutLval, RedoLayoutStr),
		LayoutAddrStr =
			layout_out__make_label_layout_name(RedoLayoutLabel),
		string__append_list([
			FillSlotsUptoIoSeq,
			"\t\t", RedoLayoutStr,
				" = (MR_Word) (const MR_Word *) &",
				LayoutAddrStr, ";\n"
		], FillSlotsUptoRedo),
		MaybeLayoutLabel = yes(RedoLayoutLabel)
	;
		MaybeRedoLabel = no,
		FillSlotsUptoRedo = FillSlotsUptoIoSeq,
		MaybeLayoutLabel = no
	),
	(
		% This could be done by generating proper LLDS instead of C.
		% However, in shallow traced code we want to execute this
		% only when the caller is deep traced, and everything inside
		% that test must be in C code.
		MaybeTrailLvals = yes(TrailLval - TicketLval),
		trace__stackref_to_string(TrailLval, TrailLvalStr),
		trace__stackref_to_string(TicketLval, TicketLvalStr),
		string__append_list([
			FillSlotsUptoRedo,
			"\t\tMR_mark_ticket_stack(", TicketLvalStr, ");\n",
			"\t\tMR_store_ticket(", TrailLvalStr, ");\n"
		], FillSlotsUptoTrail)
	;
		MaybeTrailLvals = no,
		FillSlotsUptoTrail = FillSlotsUptoRedo
	),
	(
		MaybeFromFullSlot = yes(CallFromFullSlot),
		trace__stackref_to_string(CallFromFullSlot,
			CallFromFullSlotStr),
		string__append_list([
			"\t\t", CallFromFullSlotStr, " = MR_trace_from_full;\n",
			"\t\tif (MR_trace_from_full) {\n",
			FillSlotsUptoTrail,
			"\t\t} else {\n",
			"\t\t\t", CallDepthStr, " = MR_trace_call_depth;\n",
			"\t\t}\n"
		], TraceStmt1)
	;
		MaybeFromFullSlot = no,
		TraceStmt1 = FillSlotsUptoTrail
	),
	TraceCode1 = node([
		pragma_c([], [pragma_c_raw_code(TraceStmt1,
			live_lvals_info(set__init))], will_not_call_mercury,
			no, no, MaybeLayoutLabel, no, yes, no)
			- ""
	]),
	(
		MaybeMaxfrLval = yes(MaxfrLval),
		TraceCode2 = node([
			assign(MaxfrLval, lval(maxfr)) - "save initial maxfr"
		])
	;
		MaybeMaxfrLval = no,
		TraceCode2 = empty
	),
	(
		MaybeCallTableLval = yes(CallTableLval),
		trace__stackref_to_string(CallTableLval, CallTableLvalStr),
		string__append_list([
			"\t\t", CallTableLvalStr, " = 0;\n"
		], TraceStmt3),
		TraceCode3 = node([
			pragma_c([], [pragma_c_raw_code(TraceStmt3,
				live_lvals_info(set__init))],
				will_not_call_mercury, no, no, no, no, yes, no)
				- ""
		])
	;
		MaybeCallTableLval = no,
		TraceCode3 = empty
	),
	TraceCode = tree(TraceCode1, tree(TraceCode2, TraceCode3)).

trace__prepare_for_call(CI, TraceCode) :-
	code_info__get_maybe_trace_info(CI, MaybeTraceInfo),
	CodeModel = code_info__get_proc_model(CI),
	(
		MaybeTraceInfo = yes(TraceInfo)
	->
		MaybeFromFullSlot = TraceInfo ^ from_full_lval,
		trace__call_depth_slot(CodeModel, CallDepthLval),
		trace__stackref_to_string(CallDepthLval, CallDepthStr),
		(
			MaybeFromFullSlot = yes(_),
			MacroStr = "MR_trace_reset_depth_from_shallow"
		;
			MaybeFromFullSlot = no,
			MacroStr = "MR_trace_reset_depth_from_full"
		),
		string__append_list([
			MacroStr, "(", CallDepthStr, ");\n"
		], ResetStmt),
		TraceCode = node([
			c_code(ResetStmt, live_lvals_info(set__init))
				- ""
		])
	;
		TraceCode = empty
	).

trace__maybe_generate_internal_event_code(Goal, OutsideGoalInfo, Code, !CI) :-
	code_info__get_maybe_trace_info(!.CI, MaybeTraceInfo),
	( MaybeTraceInfo = yes(TraceInfo) ->
		Goal = _ - GoalInfo,
		goal_info_get_goal_path(GoalInfo, Path),
		(
			Path = [LastStep | _],
			(
				LastStep = switch(_, _),
				PortPrime = switch
			;
				LastStep = disj(_),
				PortPrime = disj
			;
				LastStep = ite_cond,
				PortPrime = ite_cond
			;
				LastStep = ite_then,
				PortPrime = ite_then
			;
				LastStep = ite_else,
				PortPrime = ite_else
			;
				LastStep = neg,
				PortPrime = neg_enter
			)
		->
			Port = PortPrime
		;
			error("trace__generate_internal_event_code: bad path")
		),
		(
			code_info__get_pred_info(!.CI, PredInfo),
			code_info__get_proc_info(!.CI, ProcInfo),
			eff_trace_needs_port(PredInfo, ProcInfo,
				TraceInfo ^ trace_level,
				TraceInfo ^ trace_suppress_items, Port) = yes
		->
			goal_info_get_pre_deaths(GoalInfo, PreDeaths),
			goal_info_get_context(GoalInfo, Context),
			(
				goal_info_has_feature(OutsideGoalInfo,
					hide_debug_event)
			->
				HideEvent = yes
			;
				HideEvent = no
			),
			trace__generate_event_code(Port,
				internal(Path, PreDeaths), TraceInfo,
				Context, HideEvent, _, _, Code, !CI)
		;
			Code = empty
		)
	;
		Code = empty
	).

trace__maybe_generate_negated_event_code(Goal, OutsideGoalInfo, NegPort, Code,
		!CI) :-
	code_info__get_maybe_trace_info(!.CI, MaybeTraceInfo),
	(
		MaybeTraceInfo = yes(TraceInfo),
		(
			NegPort = neg_failure,
			Port = neg_failure
		;
			NegPort = neg_success,
			Port = neg_success
		),
		code_info__get_pred_info(!.CI, PredInfo),
		code_info__get_proc_info(!.CI, ProcInfo),
		eff_trace_needs_port(PredInfo, ProcInfo,
			TraceInfo ^ trace_level,
			TraceInfo ^ trace_suppress_items, Port) = yes
	->
		Goal = _ - GoalInfo,
		goal_info_get_goal_path(GoalInfo, Path),
		goal_info_get_context(GoalInfo, Context),
		( goal_info_has_feature(OutsideGoalInfo, hide_debug_event) ->
			HideEvent = yes
		;
			HideEvent = no
		),
		trace__generate_event_code(Port, negation_end(Path),
			TraceInfo, Context, HideEvent, _, _, Code, !CI)
	;
		Code = empty
	).

trace__maybe_generate_pragma_event_code(PragmaPort, Context, Code, !CI) :-
	code_info__get_maybe_trace_info(!.CI, MaybeTraceInfo),
	(
		MaybeTraceInfo = yes(TraceInfo),
		trace__convert_nondet_pragma_port_type(PragmaPort, Port),
		code_info__get_pred_info(!.CI, PredInfo),
		code_info__get_proc_info(!.CI, ProcInfo),
		eff_trace_needs_port(PredInfo, ProcInfo,
			TraceInfo ^ trace_level,
			TraceInfo ^ trace_suppress_items, Port) = yes
	->
		trace__generate_event_code(Port, nondet_pragma, TraceInfo,
			Context, no, _, _, Code, !CI)
	;
		Code = empty
	).

trace__generate_external_event_code(ExternalPort, TraceInfo, Context,
		MaybeExternalInfo, !CI) :-
	trace__convert_external_port_type(ExternalPort, Port),
	(
		code_info__get_pred_info(!.CI, PredInfo),
		code_info__get_proc_info(!.CI, ProcInfo),
		eff_trace_needs_port(PredInfo, ProcInfo,
			TraceInfo ^ trace_level,
			TraceInfo ^ trace_suppress_items, Port) = yes
	->
		trace__generate_event_code(Port, external, TraceInfo,
			Context, no, Label, TvarDataMap, Code, !CI),
		MaybeExternalInfo = yes(external_event_info(Label,
			TvarDataMap, Code))
	;
		MaybeExternalInfo = no
	).

:- pred trace__generate_event_code(trace_port::in, trace_port_info::in,
	trace_info::in, prog_context::in, bool::in, label::out,
	map(tvar, set(layout_locn))::out, code_tree::out,
	code_info::in, code_info::out) is det.

trace__generate_event_code(Port, PortInfo, TraceInfo, Context, HideEvent,
		Label, TvarDataMap, Code, !CI) :-
	code_info__get_next_label(Label, !CI),
	code_info__get_known_variables(!.CI, LiveVars0),
	(
		PortInfo = external,
		LiveVars = LiveVars0,
		Path = []
	;
		PortInfo = internal(Path, PreDeaths),
		ResumeVars = code_info__current_resume_point_vars(!.CI),
		set__difference(PreDeaths, ResumeVars, RealPreDeaths),
		set__to_sorted_list(RealPreDeaths, RealPreDeathList),
		list__delete_elems(LiveVars0, RealPreDeathList, LiveVars)
	;
		PortInfo = negation_end(Path),
		LiveVars = LiveVars0
	;
		PortInfo = nondet_pragma,
		LiveVars = [],
		( Port = nondet_pragma_first ->
			Path = [first]
		; Port = nondet_pragma_later ->
			Path = [later]
		;
			error("bad nondet pragma port")
		)
	),
	VarTypes = code_info__get_var_types(!.CI),
	code_info__get_varset(!.CI, VarSet),
	code_info__get_instmap(!.CI, InstMap),
	trace__produce_vars(LiveVars, VarSet, VarTypes, InstMap, Port,
		set__init, TvarSet, [], VarInfoList, ProduceCode, !CI),
	code_info__max_reg_in_use(!.CI, MaxReg),
	code_info__get_max_reg_in_use_at_trace(!.CI, MaxTraceReg0),
	( MaxTraceReg0 < MaxReg ->
		code_info__set_max_reg_in_use_at_trace(MaxReg, !CI)
	;
		true
	),
	code_info__variable_locations(!.CI, VarLocs),
	code_info__get_proc_info(!.CI, ProcInfo),
	set__to_sorted_list(TvarSet, TvarList),
	continuation_info__find_typeinfos_for_tvars(TvarList,
		VarLocs, ProcInfo, TvarDataMap),

	% compute the set of live lvals at the event
	VarLvals = list__map(find_lval_in_var_info, VarInfoList),
	map__values(TvarDataMap, TvarLocnSets),
	TvarLocnSet = set__union_list(TvarLocnSets),
	set__to_sorted_list(TvarLocnSet, TvarLocns),
	TvarLvals = list__map(find_lval_in_layout_locn, TvarLocns),
	list__append(VarLvals, TvarLvals, LiveLvals),
	LiveLvalSet = set__list_to_set(LiveLvals),

	set__list_to_set(VarInfoList, VarInfoSet),
	LayoutLabelInfo = layout_label_info(VarInfoSet, TvarDataMap),
	LabelStr = llds_out__label_to_c_string(Label, no),
	string__append_list(["\t\tMR_EVENT(", LabelStr, ")\n"], TraceStmt),
	code_info__add_trace_layout_for_label(Label, Context, Port, HideEvent,
		Path, LayoutLabelInfo, !CI),
	(
		Port = fail,
		TraceInfo ^ redo_label = yes(RedoLabel)
	->
		% The layout information for the redo event is the same as
		% for the fail event; all the non-clobbered inputs in their
		% stack slots. It is convenient to generate this common layout
		% when the code generator state is set up for the fail event;
		% generating it for the redo event would be much harder.
		% On the other hand, the address of the layout structure
		% for the redo event should be put into its fixed stack slot
		% at procedure entry. Therefore trace__setup reserves a label
		% for the redo event, whose layout information is filled in
		% when we get to the fail event.
		code_info__add_trace_layout_for_label(RedoLabel, Context, redo,
			HideEvent, Path, LayoutLabelInfo, !CI)
	;
		true
	),
	TraceCode =
		node([
			label(Label)
				- "A label to hang trace liveness on",
				% Referring to the label from the pragma_c
				% prevents the label from being renamed
				% or optimized away.
				% The label is before the trace code
				% because sometimes this pair is preceded
				% by another label, and this way we can
				% eliminate this other label.
			pragma_c([], [pragma_c_raw_code(TraceStmt,
				live_lvals_info(LiveLvalSet))],
				may_call_mercury, no, no, yes(Label), no, yes,
				no)
				- ""
		]),
	Code = tree(ProduceCode, TraceCode).

:- func find_lval_in_var_info(layout_var_info) = lval.

find_lval_in_var_info(layout_var_info(LayoutLocn, _, _)) =
	find_lval_in_layout_locn(LayoutLocn).

:- func find_lval_in_layout_locn(layout_locn) = lval.

find_lval_in_layout_locn(direct(Lval)) = Lval.
find_lval_in_layout_locn(indirect(Lval, _)) = Lval.

trace__maybe_setup_redo_event(TraceInfo, Code) :-
	TraceRedoLabel = TraceInfo ^ redo_label,
	( TraceRedoLabel = yes(_) ->
		MaybeFromFullSlot = TraceInfo ^ from_full_lval,
		(
			MaybeFromFullSlot = yes(Lval),
			% The code in the runtime looks for the from-full
			% flag in framevar 5; see the comment before
			% trace__reserved_slots.
			require(unify(Lval, framevar(5)),
				"from-full flag not stored in expected slot"),
			Code = node([
				mkframe(temp_frame(nondet_stack_proc),
					yes(do_trace_redo_fail_shallow))
					- "set up shallow redo event"
			])
		;
			MaybeFromFullSlot = no,
			Code = node([
				mkframe(temp_frame(nondet_stack_proc),
					yes(do_trace_redo_fail_deep))
					- "set up deep redo event"
			])
		)
	;
		Code = empty
	).

:- pred trace__produce_vars(list(prog_var)::in, prog_varset::in, vartypes::in,
	instmap::in, trace_port::in, set(tvar)::in, set(tvar)::out,
	list(layout_var_info)::in, list(layout_var_info)::out,
	code_tree::out, code_info::in, code_info::out) is det.

trace__produce_vars([], _, _, _, _, !TVars, !VarInfos, empty, !CI).
trace__produce_vars([Var | Vars], VarSet, VarTypes, InstMap, Port,
		!TVars, !VarInfos, tree(VarCode, VarsCode), !CI) :-
	map__lookup(VarTypes, Var, Type),
	( is_dummy_argument_type(Type) ->
		VarCode = empty
	;
		trace__produce_var(Var, VarSet, InstMap, !TVars,
			VarInfo, VarCode, !CI),
		!:VarInfos = [VarInfo | !.VarInfos]
	),
	trace__produce_vars(Vars, VarSet, VarTypes, InstMap, Port, !TVars,
		!VarInfos, VarsCode, !CI).

:- pred trace__produce_var(prog_var::in, prog_varset::in, instmap::in,
	set(tvar)::in, set(tvar)::out, layout_var_info::out, code_tree::out,
	code_info::in, code_info::out) is det.

trace__produce_var(Var, VarSet, InstMap, !Tvars, VarInfo, VarCode, !CI) :-
	code_info__produce_variable_in_reg_or_stack(Var, VarCode, Lval, !CI),
	Type = code_info__variable_type(!.CI, Var),
	code_info__get_module_info(!.CI, ModuleInfo),
	( varset__search_name(VarSet, Var, SearchName) ->
		Name = SearchName
	;
		Name = ""
	),
	instmap__lookup_var(InstMap, Var, Inst),
	( inst_match__inst_is_ground(ModuleInfo, Inst) ->
		LldsInst = ground
	;
		LldsInst = partial(Inst)
	),
	LiveType = var(Var, Name, Type, LldsInst),
	VarInfo = layout_var_info(direct(Lval), LiveType, "trace"),
	type_util__real_vars(Type, TypeVars),
	set__insert_list(!.Tvars, TypeVars, !:Tvars).

%-----------------------------------------------------------------------------%

:- pred trace__build_fail_vars(list(prog_var)::in, list(inst)::in,
	list(arg_info)::in, module_info::in, vartypes::in,
	list(prog_var)::out) is semidet.

trace__build_fail_vars([], [], [], _, _, []).
trace__build_fail_vars([Var | Vars], [Inst | Insts], [Info | Infos],
		ModuleInfo, VarTypes, FailVars) :-
	trace__build_fail_vars(Vars, Insts, Infos, ModuleInfo, VarTypes,
		FailVars0),
	Info = arg_info(_Loc, ArgMode),
	(
		ArgMode = top_in,
		\+ inst_is_clobbered(ModuleInfo, Inst),
		map__lookup(VarTypes, Var, Type),
		\+ is_dummy_argument_type(Type)
	->
		FailVars = [Var | FailVars0]
	;
		FailVars = FailVars0
	).

%-----------------------------------------------------------------------------%

:- pred trace__code_model_to_string(code_model::in, string::out) is det.

trace__code_model_to_string(model_det,  "MR_MODEL_DET").
trace__code_model_to_string(model_semi, "MR_MODEL_SEMI").
trace__code_model_to_string(model_non,  "MR_MODEL_NON").

:- pred trace__stackref_to_string(lval::in, string::out) is det.

trace__stackref_to_string(Lval, LvalStr) :-
	( Lval = stackvar(Slot) ->
		string__int_to_string(Slot, SlotString),
		string__append_list(["MR_sv(", SlotString, ")"], LvalStr)
	; Lval = framevar(Slot) ->
		string__int_to_string(Slot, SlotString),
		string__append_list(["MR_fv(", SlotString, ")"], LvalStr)
	;
		error("non-stack lval in stackref_to_string")
	).

%-----------------------------------------------------------------------------%

:- pred trace__convert_external_port_type(external_trace_port::in,
	trace_port::out) is det.

trace__convert_external_port_type(call, call).
trace__convert_external_port_type(exit, exit).
trace__convert_external_port_type(fail, fail).

:- pred trace__convert_nondet_pragma_port_type(nondet_pragma_trace_port::in,
	trace_port::out) is det.

trace__convert_nondet_pragma_port_type(nondet_pragma_first,
	nondet_pragma_first).
trace__convert_nondet_pragma_port_type(nondet_pragma_later,
	nondet_pragma_later).

%-----------------------------------------------------------------------------%

:- pred trace__event_num_slot(code_model::in, lval::out) is det.
:- pred trace__call_num_slot(code_model::in, lval::out) is det.
:- pred trace__call_depth_slot(code_model::in, lval::out) is det.
:- pred trace__redo_layout_slot(code_model::in, lval::out) is det.

trace__event_num_slot(CodeModel, EventNumSlot) :-
	( CodeModel = model_non ->
		EventNumSlot  = framevar(1)
	;
		EventNumSlot  = stackvar(1)
	).

trace__call_num_slot(CodeModel, CallNumSlot) :-
	( CodeModel = model_non ->
		CallNumSlot   = framevar(2)
	;
		CallNumSlot   = stackvar(2)
	).

trace__call_depth_slot(CodeModel, CallDepthSlot) :-
	( CodeModel = model_non ->
		CallDepthSlot = framevar(3)
	;
		CallDepthSlot = stackvar(3)
	).

trace__redo_layout_slot(CodeModel, RedoLayoutSlot) :-
	( CodeModel = model_non ->
		RedoLayoutSlot = framevar(4)
	;
		error("attempt to access redo layout slot " ++
			"for det or semi procedure")
	).

%-----------------------------------------------------------------------------%

	% Information for tracing that is valid throughout the execution
	% of a procedure.
:- type trace_info --->
	trace_info(
		trace_level		:: trace_level,
		trace_suppress_items	:: trace_suppress_items,
		from_full_lval		:: maybe(lval),
					% If the trace level is shallow,
					% the lval of the slot that holds the
					% from-full flag.
		io_seq_lval		:: maybe(lval),
					% If the procedure has I/O state
					% arguments, the lval of the slot
					% that holds the initial value of the
					% I/O action counter.
		trail_lvals		:: maybe(pair(lval)),
					% If trailing is enabled, the lvals
					% of the slots that hold the value
					% of the trail pointer and the ticket
					% counter at the time of the call.
		maxfr_lval		:: maybe(lval),
					% If we reserve a slot for holding
					% the value of maxfr at entry for use
					% in implementing retry, the lval of
					% the slot.
		call_table_tip_lval	:: maybe(lval),
					% If we reserve a slot for holding
					% the value of the call table tip
					% variable, the lval of this variable.
		redo_label		:: maybe(label)
					% If we are generating redo events,
					% this has the label associated with
					% the fail event, which we then reserve
					% in advance, so we can put the
					% address of its layout struct
					% into the slot which holds the
					% layout for the redo event (the
					% two events have identical layouts).
	).
