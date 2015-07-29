%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1996-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: module_imports.m.
% Main author: fjh.
%
% This module contains the data structure for recording module imports
% and its access predicates.
%
%-----------------------------------------------------------------------------%

:- module parse_tree.module_imports.
:- interface.

:- import_module libs.file_util.
:- import_module libs.globals.
:- import_module libs.timestamp.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.error_util.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_item.
:- import_module parse_tree.prog_io_error.
:- import_module parse_tree.status.

:- import_module cord.
:- import_module list.
:- import_module map.
:- import_module maybe.

%-----------------------------------------------------------------------------%

    % When doing smart recompilation record for each module the suffix of
    % the file that was read and the modification time of the file.
    %
:- type module_timestamp_map == map(module_name, module_timestamp).
:- type module_timestamp
    --->    module_timestamp(
                mts_file_kind       :: file_kind,
                mts_timestamp       :: timestamp,
                mts_need_qualifier  :: need_qualifier
            ).

    % The `module_and_imports' structure holds information about
    % a module and the modules that it imports.
    %
    % Note that we build this structure up as we go along.
    % When generating the dependencies (for `--generate-dependencies'), the
    % two fields that hold the direct imports do not include the imports via
    % ancestors when the module is first read in; the ancestor imports are
    % added later, once all the modules have been read in. Similarly the
    % indirect imports field is initially set to the empty list and filled
    % in later.
    %
    % When compiling or when making interface files, the same sort of thing
    % applies: initially all the list(module_name) fields except the public
    % children field are set to empty lists, and then we add ancestor
    % modules and imported modules to their respective lists as we process
    % the interface files for those imported or ancestor modules.
    %
:- type module_and_imports
    --->    module_and_imports(
                % The source file.
                mai_source_file_name            :: file_name,

                % The name of the top-level module in the source file
                % containing the module that we are compiling.
                mai_source_file_module_name     :: module_name,

                % The module (or sub-module) that we are compiling.
                mai_module_name                 :: module_name,

                % The context of the module declaration of mai_module_name.
                mai_module_name_context         :: prog_context,

                % The list of ancestor modules it inherits.
                mai_parent_deps                 :: list(module_name),

                % The list of modules it directly imports in the interface
                % (imports via ancestors count as direct).
                mai_int_deps                    :: list(module_name),

                % The list of modules it directly imports in the
                % implementation.
                mai_impl_deps                   :: list(module_name),

                % The list of modules it indirectly imports.
                mai_indirect_deps               :: list(module_name),

                mai_children                    :: list(module_name),

                % The list of its public children, i.e. child modules that
                % it includes in the interface section.
                mai_public_children             :: list(module_name),

                % The modules included in the same source file. This field
                % is only set for the top-level module in each file.
                mai_nested_children             :: list(module_name),

                % The list of filenames for fact tables in this module.
                mai_fact_table_deps             :: list(string),

                % The `:- pragma foreign_import_module' declarations.
                mai_foreign_import_modules      :: foreign_import_module_infos,

                % The list of filenames referenced by `:- pragma foreign_decl'
                % or `:- pragma foreign_code' declarations.
                mai_foreign_include_files       :: foreign_include_file_infos,

                % Whether or not the module contains foreign code, and if yes,
                % which languages they use.
                mai_has_foreign_code            :: contains_foreign_code,

                % Does the module contain any `:- pragma foreign_export'
                % declarations?
                mai_contains_foreign_export     :: contains_foreign_export,

                % The contents of the module and its imports.
                mai_blocks_cord                 :: cord(aug_item_block),

                % Whether an error has been encountered when reading in
                % this module.
                mai_specs                       :: list(error_spec),
                mai_errors                      :: read_module_errors,

                % If we are doing smart recompilation, we need to keep
                % the timestamps of the modules read in.
                mai_maybe_timestamp_map         :: maybe(module_timestamp_map),

                % Does this module contain main/2?
                mai_has_main                    :: has_main,

                % The directory containing the module source.
                mai_module_dir                  :: dir_name
            ).

:- pred module_and_imports_get_source_file_name(module_and_imports::in,
    file_name::out) is det.
:- pred module_and_imports_get_module_name(module_and_imports::in,
    module_name::out) is det.
:- pred module_and_imports_get_module_name_context(module_and_imports::in,
    prog_context::out) is det.
:- pred module_and_imports_get_impl_deps(module_and_imports::in,
    list(module_name)::out) is det.

    % Set the interface dependencies.
    %
:- pred module_and_imports_set_int_deps(list(module_name)::in,
    module_and_imports::in, module_and_imports::out) is det.

    % Set the implementation dependencies.
    %
:- pred module_and_imports_set_impl_deps(list(module_name)::in,
    module_and_imports::in, module_and_imports::out) is det.

    % Set the indirect dependencies.
    %
:- pred module_and_imports_set_indirect_deps(list(module_name)::in,
    module_and_imports::in, module_and_imports::out) is det.

:- pred module_and_imports_set_errors(read_module_errors::in,
    module_and_imports::in, module_and_imports::out) is det.

:- pred module_and_imports_add_specs(list(error_spec)::in,
    module_and_imports::in, module_and_imports::out) is det.

:- pred module_and_imports_add_interface_error(read_module_errors::in,
    module_and_imports::in, module_and_imports::out) is det.

    % Add items to the end of the list.
    %
:- pred module_and_imports_add_item_blocks(list(aug_item_block)::in,
    module_and_imports::in, module_and_imports::out) is det.

    % Do the job of
    %   module_and_imports_add_item_blocks
    %   module_and_imports_add_specs
    %   module_and_imports_add_interface_error
    % all at once.
    %
:- pred module_and_imports_add_item_blocks_specs_errors(
    list(aug_item_block)::in, list(error_spec)::in, read_module_errors::in,
    module_and_imports::in, module_and_imports::out) is det.

    % Return the results recorded in the module_and_imports structure.
    %
    % There is no predicate to return *just* the items, since that would
    % allow callers to forget to retrieve and then print the error
    % specifications.
    %
:- pred module_and_imports_get_results(module_and_imports::in,
    list(aug_item_block)::out, list(error_spec)::out, read_module_errors::out)
    is det.

%-----------------------------------------------------------------------------%

    % init_module_and_imports(Globals, FileName, SourceFileModuleName,
    %   NestedModuleNames, Specs, Errors, CompilationUnit, ModuleImports).
    %
:- pred init_module_and_imports(globals::in, file_name::in, module_name::in,
    list(module_name)::in, list(error_spec)::in, read_module_errors::in,
    raw_compilation_unit::in, module_and_imports::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module mdbcomp.prim_data.
:- import_module parse_tree.comp_unit_interface.
:- import_module parse_tree.get_dependencies.
:- import_module parse_tree.modules.    % undesirable dependency

:- import_module dir.
:- import_module set.
:- import_module term.

%-----------------------------------------------------------------------------%

module_and_imports_get_source_file_name(Module, X) :-
    X = Module ^ mai_source_file_name.
module_and_imports_get_module_name(Module, X) :-
    X = Module ^ mai_module_name.
module_and_imports_get_module_name_context(Module, X) :-
    X = Module ^ mai_module_name_context.
module_and_imports_get_impl_deps(Module, X) :-
    X = Module ^ mai_impl_deps.

module_and_imports_set_int_deps(IntDeps, !Module) :-
    !Module ^ mai_int_deps := IntDeps.
module_and_imports_set_impl_deps(ImplDeps, !Module) :-
    !Module ^ mai_impl_deps := ImplDeps.
module_and_imports_set_indirect_deps(IndirectDeps, !Module) :-
    !Module ^ mai_indirect_deps := IndirectDeps.
module_and_imports_set_errors(Errors, !Module) :-
    !Module ^ mai_errors := Errors.

module_and_imports_add_specs(NewSpecs, !Module) :-
    Specs0 = !.Module ^ mai_specs,
    Specs = NewSpecs ++ Specs0,
    !Module ^ mai_specs := Specs.

module_and_imports_add_interface_error(InterfaceErrors, !Module) :-
    Errors0 = !.Module ^ mai_errors,
    set.union(Errors0, InterfaceErrors, Errors),
    !Module ^ mai_errors := Errors.

module_and_imports_add_item_blocks(NewItemBlocks, !Module) :-
    ItemBlocks0 = !.Module ^ mai_blocks_cord,
    ItemBlocks = ItemBlocks0 ++ cord.from_list(NewItemBlocks),
    !Module ^ mai_blocks_cord := ItemBlocks.

module_and_imports_add_item_blocks_specs_errors(NewItemBlocks,
        NewSpecs, InterfaceErrors, !Module) :-
    ItemBlocks0 = !.Module ^ mai_blocks_cord,
    Specs0 = !.Module ^ mai_specs,
    Errors0 = !.Module ^ mai_errors,
    ItemBlocks = ItemBlocks0 ++ cord.from_list(NewItemBlocks),
    Specs = NewSpecs ++ Specs0,
    set.union(Errors0, InterfaceErrors, Errors),
    !Module ^ mai_blocks_cord := ItemBlocks,
    !Module ^ mai_specs := Specs,
    !Module ^ mai_errors := Errors.

module_and_imports_get_results(Module, ItemBlocks, Specs, Errors) :-
    ItemBlocks = cord.list(Module ^ mai_blocks_cord),
    Specs = Module ^ mai_specs,
    Errors = Module ^ mai_errors.

%-----------------------------------------------------------------------------%

init_module_and_imports(Globals, FileName, SourceFileModuleName,
        NestedModuleNames, Specs, Errors, RawCompilationUnit, ModuleImports) :-
    RawCompilationUnit = compilation_unit(ModuleName, ModuleNameContext,
        RawItemBlocks),
    ParentDeps = get_ancestors(ModuleName),

    get_dependencies_in_item_blocks(RawItemBlocks,
        ImplImportDeps0, ImplUseDeps0),
    get_implicit_dependencies_in_item_blocks(Globals, RawItemBlocks,
        ImplicitImplImportDeps, ImplicitImplUseDeps),
    ImplImportDeps = ImplicitImplImportDeps ++ ImplImportDeps0,
    ImplUseDeps = ImplicitImplUseDeps ++ ImplUseDeps0,
    ImplementationDeps = ImplImportDeps ++ ImplUseDeps,

    get_interface(dont_include_impl_types, RawCompilationUnit,
        InterfaceItemBlocks),
    get_dependencies_in_item_blocks(InterfaceItemBlocks,
        InterfaceImportDeps0, InterfaceUseDeps0),
    get_implicit_dependencies_in_item_blocks(Globals, InterfaceItemBlocks,
        ImplicitInterfaceImportDeps, ImplicitInterfaceUseDeps),
    InterfaceImportDeps = ImplicitInterfaceImportDeps ++ InterfaceImportDeps0,
    InterfaceUseDeps = ImplicitInterfaceUseDeps ++ InterfaceUseDeps0,
    InterfaceDeps = InterfaceImportDeps ++ InterfaceUseDeps,

    % We don't fill in the indirect dependencies yet.
    IndirectDeps = [],

    get_included_modules_in_item_blocks(RawItemBlocks, IncludeDeps),
    get_included_modules_in_item_blocks(InterfaceItemBlocks,
        InterfaceIncludeDeps),

    % XXX ITEM_LIST Document why we do this.
    ( ModuleName = SourceFileModuleName ->
        list.delete_all(NestedModuleNames, ModuleName, NestedDeps)
    ;
        NestedDeps = []
    ),

    get_fact_table_dependencies_in_item_blocks(RawItemBlocks, FactTableDeps),

    % Figure out whether the items contain foreign code.
    get_foreign_code_indicators_from_item_blocks(Globals, RawItemBlocks,
        LangSet, ForeignImports0, ForeignIncludeFiles, ContainsForeignExport),
    ( set.is_empty(LangSet) ->
        ContainsForeignCode = contains_no_foreign_code
    ;
        ContainsForeignCode = contains_foreign_code(LangSet)
    ),

    % If this module contains `:- pragma foreign_export' or
    % `:- pragma foreign_type' declarations, importing modules may need
    % to import its `.mh' file.
    get_foreign_self_imports_from_item_blocks(RawItemBlocks, SelfImportLangs),
    ForeignSelfImports = list.map(
        (func(Lang) = foreign_import_module_info(Lang, ModuleName,
            term.context_init)),
        SelfImportLangs),
    ForeignImports = cord.from_list(ForeignSelfImports) ++ ForeignImports0,

    % Work out whether the items contain main/2.
    look_for_main_pred_in_item_blocks(RawItemBlocks, no_main, HasMain),
    % XXX ITEM_LIST ItemBlocks is NOT stored here, per the documentation above.
    % Maybe it should be.
    ModuleImports = module_and_imports(FileName, SourceFileModuleName,
        ModuleName, ModuleNameContext, ParentDeps, InterfaceDeps,
        ImplementationDeps, IndirectDeps, IncludeDeps,
        InterfaceIncludeDeps, NestedDeps, FactTableDeps,
        ForeignImports, ForeignIncludeFiles,
        ContainsForeignCode, ContainsForeignExport,
        cord.empty, Specs, Errors, no, HasMain, dir.this_directory).

:- pred look_for_main_pred_in_item_blocks(list(item_block(MS))::in,
    has_main::in, has_main::out) is det.

look_for_main_pred_in_item_blocks([], !HasMain).
look_for_main_pred_in_item_blocks([ItemBlock | ItemBlocks], !HasMain) :-
    % XXX ITEM_LIST Warn if Section isn't ms_interface or ams_interface.
    ItemBlock = item_block(_Section, _Context, Items),
    look_for_main_pred_in_items(Items, !HasMain),
    look_for_main_pred_in_item_blocks(ItemBlocks, !HasMain).

:- pred look_for_main_pred_in_items(list(item)::in,
    has_main::in, has_main::out) is det.

look_for_main_pred_in_items([], !HasMain).
look_for_main_pred_in_items([Item | Items], !HasMain) :-
    ( if
        Item = item_pred_decl(ItemPredDecl),
        ItemPredDecl = item_pred_decl_info(Name, pf_predicate, ArgTypes,
            _, WithType, _, _, _, _, _, _, _, _, _),
        unqualify_name(Name) = "main",
        % XXX We should allow `main/2' to be declared using `with_type`,
        % but equivalences haven't been expanded at this point.
        % The `has_main' field is only used for some special case handling
        % of the module containing main for the IL backend (we generate
        % a `.exe' file rather than a `.dll' file). This would arguably
        % be better done by generating a `.dll' file as normal, and a
        % separate `.exe' file containing initialization code and a call
        % to `main/2', as we do with the `_init.c' file in the C backend.
        ArgTypes = [_, _],
        WithType = no
    then
        % XXX ITEM_LIST Should we warn if !.HasMain = has_main?
        % If not, then we should stop recursing right here.
        !:HasMain = has_main
    else
        true
    ),
    look_for_main_pred_in_items(Items, !HasMain).

%-----------------------------------------------------------------------------%
:- end_module parse_tree.module_imports.
%-----------------------------------------------------------------------------%
