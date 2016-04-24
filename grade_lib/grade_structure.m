%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%
% Copyright (C) 2016 The Mercury team.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% The grade structure is intended to be the tightest possible type
% for representing grades. The intention is that
%
% - the grade structure should be able to represent ALL valid grades, and
% - the grade structure should be able to represent NO invalid grades.
%
% The idea is that if a grade_vars term represents a valid grade,
% then it should be possible to convert it to a grade structure by calling
% grade_vars_to_grade_structure, but if it represents an invalid grade,
% the conversion will fail. Since we create grade_vars structures by
% solving partial grade specifications, and this solving process is supposed
% to generate representations of only valid grades, the failure of the
% conversion will cause grade_vars_to_grade_structure to throw an exception.
%

:- module grade_lib.grade_structure.
:- interface.

:- import_module grade_lib.grade_vars.

%---------------------------------------------------------------------------%
%
% XXX We should put the fields here into a more logical order.
% The question is: *which* logical order? The order used by
% runtime/mercury_grade.h, which is also used by other parts of the system,
% such as scripts/canonical_grade, is a historical accident, and NOT logical.
%

:- type grade_structure
    --->    grade_llds(
                grade_var_gcc_conf,
                grade_var_stack_len,
                llds_thread_safe_minmodel,
                grade_var_merc_file,
                low_tags_floats,
                grade_var_target_debug
            )
    ;       grade_mlds(
                mlds_target,
                grade_var_target_debug
            )
    ;       grade_elds(
                grade_var_ssdebug,
                grade_var_target_debug
            ).

:- type llds_thread_safe_minmodel
    --->    llds_thread_safe_no_minmodel_no(
                c_gc,
                c_trail,
                llds_perf_prof,
                grade_var_term_size_prof,
                grade_var_debug,
                llds_rbmm
                % implicitly grade_var_tscope_prof_no
            )
    ;       llds_thread_safe_no_minmodel_yes(
                llds_minmodel_kind,
                llds_minmodel_gc,
                % implicitly c_trail_no
                % implicitly llds_perf_prof_none
                % implicitly grade_var_term_size_prof_no
                grade_var_debug
                % implicitly grade_var_rbmm_no
                % implicitly grade_var_tscope_prof_no
            )
    ;       llds_thread_safe_yes_minmodel_no(
                thread_safe_c_gc,
                c_trail,                    % trailing works only in the
                                            % absence of parallel conjunction
                % implicitly llds_perf_prof_none
                % implicitly grade_var_term_size_prof_no
                % implicitly grade_var_debug_none
                % implicitly grade_var_rbmm_no
                grade_var_tscope_prof
            ).

:- type c_trail
    --->    c_trail_no
    ;       c_trail_yes(
                grade_var_trail_segments
            ).

:- type llds_minmodel_kind
    --->    lmk_stack_copy
    ;       lmk_stack_copy_debug
    ;       lmk_own_stack
    ;       lmk_own_stack_debug.

    % We could record whether we use gcc registers and gcc gotos independently.
    % (We use gcc labels only if we use gcc gots, so our choices on those
    % two grade variables are not independent.) However, we choose to use
    % this flat representation, because we may not wish to support all
    % of the possible combinations. Some gcc bugs may show up only in
    % the presence of certain combinations, and since some combinations
    % (jump, fast and asm_jump in particular) are rarely used and thus
    % not well tested, we wouldn't necessarily find out about them.
    % This flat representation allows us to pick and choose which
    % combinations we support.
:- type llds_gcc_conf                 % labels, gotos,  regs
    --->    llds_gcc_conf_none        % no      no      no
    ;       llds_gcc_conf_reg         % no      no      yes
    ;       llds_gcc_conf_jump        % no      yes     no
    ;       llds_gcc_conf_fast        % no      yes     yes
    ;       llds_gcc_conf_asm_jump    % yes     yes     no
    ;       llds_gcc_conf_asm_fast.   % yes     yes     yes

:- type c_gc
    --->    c_gc_none
    ;       c_gc_bdw
    ;       c_gc_bdw_debug
    ;       c_gc_accurate
    ;       c_gc_history.

:- type thread_safe_c_gc
    --->    thread_safe_c_gc_none
    ;       thread_safe_c_gc_bdw
    ;       thread_safe_c_gc_bdw_debug.

:- type llds_minmodel_gc
    --->    llds_mm_gc_bdw
    ;       llds_mm_gc_bdw_debug.

:- type llds_perf_prof
    --->    llds_perf_prof_none
    ;       llds_perf_prof_deep
    ;       llds_perf_prof_mprof(
                grade_var_mprof_time,
                grade_var_mprof_memory
            ).

:- type llds_rbmm
    --->    llds_rbmm_no
    ;       llds_rbmm_yes(
                grade_var_rbmm_debug,
                grade_var_rbmm_prof
            ).

:- type low_tags_floats
    --->    low_tags_floats_pregen_no(
                grade_var_low_tag_bits_use,
                grade_var_merc_float
            )
    ;       low_tags_floats_pregen_yes.
            % implies grade_var_low_tag_bits_use_2
            % implies grade_var_merc_float_is_boxed_c_double

:- type mlds_target
    --->    mlds_target_c(
                mlds_c_dararep,
                grade_var_nested_funcs,
                mlds_c_thread_safe,
                c_trail,            % XXX Is trailing compatible with threading?
                grade_var_merc_file,
                low_tags_floats
            )
    ;       mlds_target_csharp(
                grade_var_ssdebug
            )
    ;       mlds_target_java(
                grade_var_ssdebug
            ).

:- type mlds_c_dararep
    --->    mlds_c_datarep_heap_cells
    ;       mlds_c_datarep_classes.

:- type mlds_c_thread_safe
    --->    mlds_c_thread_safe_no(
                c_gc,
                mlds_c_perf_prof,
                grade_var_ssdebug
            )
    ;       mlds_c_thread_safe_yes(
                thread_safe_c_gc
                % implies no perf prof
                % implies no ssdebug
            ).

:- type mlds_c_perf_prof
    --->    mlds_c_perf_prof_none
    ;       mlds_c_perf_prof_mprof(
                grade_var_mprof_time,
                grade_var_mprof_memory
            ).

    % See the main comment at the top of the module.
    %
:- func grade_vars_to_grade_structure(grade_vars) = grade_structure.

%---------------------------------------------------------------------------%

:- implementation.

:- import_module require.
:- import_module string.

%---------------------------------------------------------------------------%

grade_vars_to_grade_structure(GradeVars) = GradeStructure :-
    % XXX We want to verify that every grade variable is used on every path,
    % for one of these three things: (a) to make a decision, (c) to check
    % that it has the expected value, or (c) to record its value in the
    % structured grade.
    %
    % We pick up the values of the arguments other than Backend in separate
    % deconstructions in each arm of the switch on Backend, to give us
    % a singleton variable warning if don't handle a grade var in an arm.
    %
    % Unfortunately, I (zs) don't see how to repeat the trick for the switch
    % on Target in the mlds case: having two deconstructs that each pick up
    % *some* arguments is vulnerable to not picking up some arguments
    % in *either*.
    GradeVars = grade_vars(Backend, _, _, _, _, _, _, _,
        _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _),

    % XXX The order of the arguments of grade_llds and grade_mls we generate
    % may differ from the order in runtime/mercury_grade.h, or the canonical
    % order when targeting non-C languages.
    % XXX We should consider imposing a standard order.
    (
        Backend = grade_var_backend_llds,

        GradeVars = grade_vars(_Backend, DataRep, Target,
            NestedFuncs, GccConf,
            LowTagBitsUse, StackLen, Trail, TrailSegments,
            MinimalModel, ThreadSafe, Gc,
            DeepProf, MprofCall, MprofTime, MprofMemory, TScopeProf,
            TermSizeProf, Debug, SSDebug, TargetDebug,
            RBMM, RBMMDebug, RBMMProf, MercFile, Pregen, MercFloat),

        expect(unify(DataRep, grade_var_datarep_heap_cells), $pred,
            "DataRep != grade_var_datarep_heap_cells"),
        expect(unify(Target, grade_var_target_c), $pred,
            "Target != grade_var_target_c"),
        expect(unify(NestedFuncs, grade_var_nested_funcs_no), $pred,
            "NestedFuncs != grade_var_nested_funcs_no"),
        expect(unify(SSDebug, grade_var_ssdebug_no), $pred,
            "SSDebug != grade_var_ssdebug_no"),
        (
            ThreadSafe = grade_var_thread_safe_target_native,
            unexpected($pred, "llds but thread_safe_target_native")
        ;
            ThreadSafe = grade_var_thread_safe_c_no,
            (
                MinimalModel = grade_var_minmodel_no,
                encode_c_gc(Gc, CGc),
                encode_c_trail(Trail, TrailSegments, CTrail),
                (
                    DeepProf = grade_var_deep_prof_no,
                    (
                        MprofCall = grade_var_mprof_call_no,
                        expect(unify(MprofTime, grade_var_mprof_time_no),
                            $pred, "MprofTime != grade_var_mprof_time_no"),
                        expect(unify(MprofMemory, grade_var_mprof_memory_no),
                            $pred, "MprofMemory != grade_var_mprof_memory_no"),
                        LLDSPerfProf = llds_perf_prof_none
                    ;
                        MprofCall = grade_var_mprof_call_yes,
                        LLDSPerfProf =
                            llds_perf_prof_mprof(MprofTime, MprofMemory)
                    )
                ;
                    DeepProf = grade_var_deep_prof_yes,
                    expect(unify(MprofCall, grade_var_mprof_call_no), $pred,
                        "MprofCall != grade_var_mprof_call_no"),
                    expect(unify(MprofTime, grade_var_mprof_time_no), $pred,
                        "MprofTime != grade_var_mprof_time_no"),
                    expect(unify(MprofMemory, grade_var_mprof_memory_no), $pred,
                        "MprofMemory != grade_var_mprof_memory_no"),
                    LLDSPerfProf = llds_perf_prof_deep
                ),
                (
                    RBMM = grade_var_rbmm_no,
                    expect(unify(RBMMDebug, grade_var_rbmm_debug_no), $pred,
                        "RBMMDebug != grade_var_rbmm_debug_no"),
                    expect(unify(RBMMProf, grade_var_rbmm_prof_no), $pred,
                        "RBMMProf != grade_var_rbmm_prof_no"),
                    LLDSRBMM = llds_rbmm_no
                ;
                    RBMM = grade_var_rbmm_yes,
                    LLDSRBMM = llds_rbmm_yes(RBMMDebug, RBMMProf)
                ),
                expect(unify(TScopeProf, grade_var_tscope_prof_no), $pred,
                    "TScopeProf != grade_var_tscope_prof_no"),
                LLDSTSMinModel = llds_thread_safe_no_minmodel_no(CGc, CTrail,
                    LLDSPerfProf, TermSizeProf, Debug, LLDSRBMM)
            ;
                (
                    MinimalModel = grade_var_minmodel_stack_copy,
                    MinimalModelKind = lmk_stack_copy
                ;
                    MinimalModel = grade_var_minmodel_stack_copy_debug,
                    MinimalModelKind = lmk_stack_copy_debug
                ;
                    MinimalModel = grade_var_minmodel_own_stack,
                    MinimalModelKind = lmk_own_stack
                ;
                    MinimalModel = grade_var_minmodel_own_stack_debug,
                    MinimalModelKind = lmk_own_stack_debug
                ),
                (
                    Gc = grade_var_gc_none,
                    unexpected($pred, "minimal model, Gc = none")
                ;
                    Gc = grade_var_gc_target_native,
                    unexpected($pred, "Target = c, Gc = target_native")
                ;
                    Gc = grade_var_gc_bdw,
                    MinModelGc = llds_mm_gc_bdw
                ;
                    Gc = grade_var_gc_bdw_debug,
                    MinModelGc = llds_mm_gc_bdw_debug
                ;
                    Gc = grade_var_gc_accurate,
                    unexpected($pred, "minimal model, Gc = accurate")
                ;
                    Gc = grade_var_gc_history,
                    unexpected($pred, "minimal model, Gc = history")
                ),
                expect(unify(Trail, grade_var_trail_no), $pred,
                    "Trail != grade_var_trail_no"),
                expect(unify(TrailSegments, grade_var_trail_segments_no), $pred,
                    "TrailSegments != grade_var_trail_segments_no"),
                expect(unify(DeepProf, grade_var_deep_prof_no), $pred,
                    "DeepProf != grade_var_deep_prof_no"),
                expect(unify(MprofCall, grade_var_mprof_call_no), $pred,
                    "MprofCall != grade_var_mprof_call_no"),
                expect(unify(MprofTime, grade_var_mprof_time_no), $pred,
                    "MprofTime != grade_var_mprof_time_no"),
                expect(unify(MprofMemory, grade_var_mprof_memory_no), $pred,
                    "MprofMemory != grade_var_mprof_memory_no"),
                expect(unify(TermSizeProf, grade_var_term_size_prof_no), $pred,
                    "TermSizeProf != grade_var_term_size_prof_no"),
                expect(unify(RBMM, grade_var_rbmm_no), $pred,
                    "RBMM != grade_var_rbmm_no"),
                expect(unify(RBMMDebug, grade_var_rbmm_debug_no), $pred,
                    "RBMMDebug != grade_var_rbmm_debug_no"),
                expect(unify(RBMMProf, grade_var_rbmm_prof_no), $pred,
                    "RBMMProf != grade_var_rbmm_prof_no"),
                LLDSTSMinModel = llds_thread_safe_no_minmodel_yes(
                    MinimalModelKind, MinModelGc, Debug)
            )
        ;
            ThreadSafe = grade_var_thread_safe_c_yes,
            expect(unify(MinimalModel, grade_var_minmodel_no), $pred,
                "MinModel != grade_var_minmodel_no"),

            encode_thread_safe_c_gc(Gc, ThreadSafeCGc),
            encode_c_trail(Trail, TrailSegments, CTrail),
            expect(unify(DeepProf, grade_var_deep_prof_no), $pred,
                "DeepProf != grade_var_deep_prof_no"),
            expect(unify(MprofCall, grade_var_mprof_call_no), $pred,
                "MprofCall != grade_var_mprof_call_no"),
            expect(unify(MprofTime, grade_var_mprof_time_no), $pred,
                "MprofTime != grade_var_mprof_time_no"),
            expect(unify(MprofMemory, grade_var_mprof_memory_no), $pred,
                "MprofMemory != grade_var_mprof_memory_no"),
            expect(unify(TermSizeProf, grade_var_term_size_prof_no), $pred,
                "TermSizeProf != grade_var_term_size_prof_no"),
            expect(unify(Debug, grade_var_debug_none), $pred,
                "Debug != grade_var_debug_none"),
            expect(unify(RBMM, grade_var_rbmm_no), $pred,
                "RBMM != grade_var_rbmm_no"),
            expect(unify(RBMMDebug, grade_var_rbmm_debug_no), $pred,
                "RBMMDebug != grade_var_rbmm_debug_no"),
            expect(unify(RBMMProf, grade_var_rbmm_prof_no), $pred,
                "RBMMProf != grade_var_rbmm_prof_no"),
            LLDSTSMinModel = llds_thread_safe_yes_minmodel_no(ThreadSafeCGc,
                CTrail, TScopeProf)
        ),
        LowTagsFloats =
            encode_low_tags_floats(Pregen, LowTagBitsUse, MercFloat),
        GradeStructure = grade_llds(GccConf, StackLen, LLDSTSMinModel,
            MercFile, LowTagsFloats, TargetDebug)
    ;
        Backend = grade_var_backend_mlds,

        GradeVars = grade_vars(_Backend, DataRep, Target,
            NestedFuncs, GccConf,
            LowTagBitsUse, StackLen, Trail, TrailSegments,
            MinimalModel, ThreadSafe, Gc,
            DeepProf, MprofCall, MprofTime, MprofMemory, TScopeProf,
            TermSizeProf, Debug, SSDebug, TargetDebug,
            RBMM, RBMMDebug, RBMMProf, MercFile, Pregen, MercFloat),

        expect(unify(GccConf, grade_var_gcc_conf_none), $pred,
            "GccConf != grade_var_gcc_conf_none"),
        expect(unify(StackLen, grade_var_stack_len_std), $pred,
            "StackLen != grade_var_stack_len_std"),
        expect(unify(MinimalModel, grade_var_minmodel_no), $pred,
            "MinimalModel != grade_var_minmodel_no"),
        expect(unify(DeepProf, grade_var_deep_prof_no), $pred,
            "DeepProf != grade_var_deep_prof_no"),
        expect(unify(TScopeProf, grade_var_tscope_prof_no), $pred,
            "TScopeProf != grade_var_tscope_prof_no"),
        expect(unify(TermSizeProf, grade_var_term_size_prof_no), $pred,
            "TermSizeProf != grade_var_term_size_prof_no"),
        expect(unify(Debug, grade_var_debug_none), $pred,
            "Debug != grade_var_debug_none"),
        expect(unify(RBMM, grade_var_rbmm_no), $pred,
            "RBMM != grade_var_rbmm_no"),
        expect(unify(RBMMDebug, grade_var_rbmm_debug_no), $pred,
            "RBMMDebug != grade_var_rbmm_debug_no"),
        expect(unify(RBMMProf, grade_var_rbmm_prof_no), $pred,
            "RBMMProf != grade_var_rbmm_prof_no"),
        (
            Target = grade_var_target_c,
            (
                DataRep = grade_var_datarep_heap_cells,
                MLDSCDataRep = mlds_c_datarep_heap_cells
            ;
                DataRep = grade_var_datarep_classes,
                MLDSCDataRep = mlds_c_datarep_classes
            ;
                DataRep = grade_var_datarep_erlang,
                unexpected($pred, "Target = c, DataRep = erlang")
            ),
            (
                ThreadSafe = grade_var_thread_safe_c_no,
                encode_c_gc(Gc, CGc),
                (
                    MprofCall = grade_var_mprof_call_no,
                    expect(unify(MprofTime, grade_var_mprof_time_no), $pred,
                        "mprof_call = no but mprof_time != no"),
                    expect(unify(MprofMemory, grade_var_mprof_memory_no), $pred,
                        "mprof_call = no but mprof_memory != no"),
                    MLDSPerfProf = mlds_c_perf_prof_none
                ;
                    MprofCall = grade_var_mprof_call_yes,
                    MLDSPerfProf =
                        mlds_c_perf_prof_mprof(MprofTime, MprofMemory)
                ),
                MLDSCThreadSafe =
                    mlds_c_thread_safe_no(CGc, MLDSPerfProf, SSDebug)
            ;
                ThreadSafe = grade_var_thread_safe_c_yes,
                encode_thread_safe_c_gc(Gc, ThreadSafeCGc),
                expect(unify(MprofCall, grade_var_mprof_call_no), $pred,
                    "thread_safe = yes but mprof_call != no"),
                expect(unify(MprofTime, grade_var_mprof_time_no), $pred,
                    "thread_safe = yes but mprof_time != no"),
                expect(unify(MprofMemory, grade_var_mprof_memory_no), $pred,
                    "thread_safe = yes but mprof_memory != no"),
                expect(unify(SSDebug, grade_var_ssdebug_no), $pred,
                    "thread_safe = yes but ssdebug != no"),
                MLDSCThreadSafe = mlds_c_thread_safe_yes(ThreadSafeCGc)
            ;
                ThreadSafe = grade_var_thread_safe_target_native,
                unexpected($pred, "mlds c but thread_safe_target_native")
            ),
            (
                Trail = grade_var_trail_no,
                CTrail = c_trail_no
            ;
                Trail = grade_var_trail_yes,
                CTrail = c_trail_yes(TrailSegments)
            ),
            LowTagsFloats =
                encode_low_tags_floats(Pregen, LowTagBitsUse, MercFloat),
            TargetC = mlds_target_c(MLDSCDataRep, NestedFuncs,
                MLDSCThreadSafe, CTrail, MercFile, LowTagsFloats),
            GradeStructure = grade_mlds(TargetC, TargetDebug)
        ;
            ( Target = grade_var_target_csharp
            ; Target = grade_var_target_java
            ),
            expect(unify(Pregen, grade_var_pregen_no), $pred,
                "Pregen != grade_var_pregen_no"),
            expect(unify(DataRep, grade_var_datarep_classes), $pred,
                "DataRep != grade_var_datarep_classes"),
            expect(unify(NestedFuncs, grade_var_nested_funcs_no), $pred,
                "NestedFuncs != grade_var_nested_funcs_no"),
            expect(unify(ThreadSafe, grade_var_thread_safe_target_native),
                $pred, "ThreadSafe != grade_var_thread_safe_target_native"),
            expect(unify(Gc, grade_var_gc_target_native), $pred,
                "Gc != grade_var_gc_target_native"),
            expect(unify(Trail, grade_var_trail_no), $pred,
                "Trail != grade_var_trail_no"),
            expect(unify(TrailSegments, grade_var_trail_segments_no), $pred,
                "TrailSegments != grade_var_trail_segments_no"),
            expect(unify(MprofCall, grade_var_mprof_call_no), $pred,
                "MprofCall != grade_var_mprof_call_no"),
            expect(unify(MprofTime, grade_var_mprof_time_no), $pred,
                "MprofTime != grade_var_mprof_time_no"),
            expect(unify(MprofMemory, grade_var_mprof_memory_no), $pred,
                "MprofMemory != grade_var_mprof_memory_no"),
            % The definition of MR_NEW_MERCURYFILE_STRUCT applies only
            % to grades that target C. When targeting other languages,
            % we don't insist on MercFile = grade_var_merc_file_no.
            expect(unify(Pregen, grade_var_pregen_no), $pred,
                "Pregen != grade_var_pregen_no"),
            (
                ( MercFloat = grade_var_merc_float_is_boxed_c_double
                ; MercFloat = grade_var_merc_float_is_unboxed_c_double
                )
                % We don't care which one. XXX Should we, on either backend?
            ;
                MercFloat = grade_var_merc_float_is_unboxed_c_float,
                unexpected($pred,
                    "MercFloat = grade_var_merc_float_is_unboxed_c_float")
            ),
            % We repeat this here in case we later add some function symbols
            % to one or both of mlds_target_csharp/mlds_target_java.
            (
                Target = grade_var_target_csharp,
                MLDSTarget = mlds_target_csharp(SSDebug)
            ;
                Target = grade_var_target_java,
                MLDSTarget = mlds_target_java(SSDebug)
            ),
            GradeStructure = grade_mlds(MLDSTarget, TargetDebug)
        ;
            Target = grade_var_target_erlang,
            unexpected($pred, "Backend = mlds but Target = erlang")
        )
    ;
        Backend = grade_var_backend_elds,

        GradeVars = grade_vars(_Backend, DataRep, Target,
            NestedFuncs, GccConf,
            _LowTagBitsUse, StackLen, Trail, TrailSegments,
            MinimalModel, ThreadSafe, Gc,
            DeepProf, MprofCall, MprofTime, MprofMemory, TScopeProf,
            TermSizeProf, Debug, SSDebug, TargetDebug,
            RBMM, RBMMDebug, RBMMProf, _MercFile, Pregen, MercFloat),

        % XXX The ELDS backend's data representation is NOT the same
        % as the LLDS backends'. If it were, we couldn't ignore the value of
        % _LowTagBitsUse.
        expect(unify(DataRep, grade_var_datarep_erlang), $pred,
            "DataRep != grade_var_datarep_erlang"),
        expect(unify(Target, grade_var_target_erlang), $pred,
            "Target != grade_var_target_erlang"),
        expect(unify(NestedFuncs, grade_var_nested_funcs_no), $pred,
            "NestedFuncs != grade_var_nested_funcs_no"),
        expect(unify(GccConf, grade_var_gcc_conf_none), $pred,
            "GccConf != grade_var_gcc_conf_none"),
        expect(unify(StackLen, grade_var_stack_len_std), $pred,
            "StackLen != grade_var_stack_len_std"),
        expect(unify(Trail, grade_var_trail_no), $pred,
            "Trail != grade_var_trail_no"),
        expect(unify(TrailSegments, grade_var_trail_segments_no), $pred,
            "TrailSegments != grade_var_trail_segments_no"),
        expect(unify(MinimalModel, grade_var_minmodel_no), $pred,
            "MinimalModel != grade_var_minmodel_no"),
        expect(unify(ThreadSafe, grade_var_thread_safe_target_native),
            $pred, "ThreadSafe != grade_var_thread_safe_target_native"),
        expect(unify(Gc, grade_var_gc_target_native), $pred,
            "Gc != grade_var_gc_target_native"),
        expect(unify(DeepProf, grade_var_deep_prof_no), $pred,
            "DeepProf != grade_var_deep_prof_no"),
        expect(unify(MprofCall, grade_var_mprof_call_no), $pred,
            "MprofCall != grade_var_mprof_call_no"),
        expect(unify(MprofTime, grade_var_mprof_time_no), $pred,
            "MprofTime != grade_var_mprof_time_no"),
        expect(unify(MprofMemory, grade_var_mprof_memory_no), $pred,
            "MprofMemory != grade_var_mprof_memory_no"),
        expect(unify(TScopeProf, grade_var_tscope_prof_no), $pred,
            "TScopeProf != grade_var_tscope_prof_no"),
        expect(unify(TermSizeProf, grade_var_term_size_prof_no), $pred,
            "TermSizeProf != grade_var_term_size_prof_no"),
        expect(unify(Debug, grade_var_debug_none), $pred,
            "Debug != grade_var_debug_none"),
        expect(unify(RBMM, grade_var_rbmm_no), $pred,
            "RBMM != grade_var_rbmm_no"),
        expect(unify(RBMMDebug, grade_var_rbmm_debug_no), $pred,
            "RBMMDebug != grade_var_rbmm_debug_no"),
        expect(unify(RBMMProf, grade_var_rbmm_prof_no), $pred,
            "RBMMProf != grade_var_rbmm_prof_no"),
        % The definition of MR_NEW_MERCURYFILE_STRUCT applies only
        % to grades that target C. When targeting other languages,
        % we don't insist on MercFile = grade_var_merc_file_no.
        expect(unify(Pregen, grade_var_pregen_no), $pred,
            "Pregen != grade_var_pregen_no"),
        (
            ( MercFloat = grade_var_merc_float_is_boxed_c_double
            ; MercFloat = grade_var_merc_float_is_unboxed_c_double
            )
            % We don't care which one. XXX Should we, on either backend?
        ;
            MercFloat = grade_var_merc_float_is_unboxed_c_float,
            unexpected($pred,
                "MercFloat = grade_var_merc_float_is_unboxed_c_float")
        ),
        % XXX probably incomplete
        GradeStructure = grade_elds(SSDebug, TargetDebug)
    ).

:- pred encode_c_gc(grade_var_gc::in, c_gc::out) is det.

encode_c_gc(Gc, CGc) :-
    (
        Gc = grade_var_gc_none,
        CGc = c_gc_none
    ;
        Gc = grade_var_gc_target_native,
        unexpected($pred, "Target = c, Gc = target_native")
    ;
        Gc = grade_var_gc_bdw,
        CGc = c_gc_bdw
    ;
        Gc = grade_var_gc_bdw_debug,
        CGc = c_gc_bdw_debug
    ;
        Gc = grade_var_gc_accurate,
        CGc = c_gc_accurate
    ;
        Gc = grade_var_gc_history,
        CGc = c_gc_history
    ).

:- pred encode_thread_safe_c_gc(grade_var_gc::in, thread_safe_c_gc::out)
    is det.

encode_thread_safe_c_gc(Gc, ThreadSafeCGc) :-
    (
        Gc = grade_var_gc_none,
        ThreadSafeCGc = thread_safe_c_gc_none
    ;
        Gc = grade_var_gc_target_native,
        unexpected($pred, "Target = c, Gc = target_native")
    ;
        Gc = grade_var_gc_bdw,
        ThreadSafeCGc = thread_safe_c_gc_bdw
    ;
        Gc = grade_var_gc_bdw_debug,
        ThreadSafeCGc = thread_safe_c_gc_bdw_debug
    ;
        Gc = grade_var_gc_accurate,
        unexpected($pred, "thread safe, Gc = accurate")
    ;
        Gc = grade_var_gc_history,
        unexpected($pred, "thread safe, Gc = history")
    ).

:- pred encode_c_trail(grade_var_trail::in, grade_var_trail_segments::in,
    c_trail::out) is det.

encode_c_trail(Trail, TrailSegments, CTrail) :-
    (
        Trail = grade_var_trail_no,
        expect(unify(TrailSegments, grade_var_trail_segments_no), $pred,
            "Trail = no, TrailSegments = yes"),
        CTrail = c_trail_no
    ;
        Trail = grade_var_trail_yes,
        CTrail = c_trail_yes(TrailSegments)
    ).

:- func encode_low_tags_floats(grade_var_pregen, grade_var_low_tag_bits_use,
    grade_var_merc_float) = low_tags_floats.

encode_low_tags_floats(Pregen, LowTagBitsUse, MercFloat) = LowTagsFloats :-
    (
        Pregen = grade_var_pregen_no,
        LowTagsFloats = low_tags_floats_pregen_no(LowTagBitsUse, MercFloat)
    ;
        Pregen = grade_var_pregen_yes,
        expect(unify(LowTagBitsUse, grade_var_low_tag_bits_use_2),
            $pred, "pregen but LowTagBitsUse != 2"),
        expect(unify(MercFloat, grade_var_merc_float_is_boxed_c_double),
            $pred, "pregen but MercFloat != boxed double"),
        LowTagsFloats = low_tags_floats_pregen_yes
    ).

%---------------------------------------------------------------------------%
:- end_module grade_lib.grade_structure.
%---------------------------------------------------------------------------%
