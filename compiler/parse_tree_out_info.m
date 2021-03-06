%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%
% Copyright (C) 2015 The Mercury team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% This module provides the basic infrastructure needed to print out
% the parse tree of a Mercury module, in whole or in part.
%
% This infrastructure has two parts.
%
% The first part of the infrastructure is the merc_out_info type. Values of
% this type control those low-level aspects of how parse tree components
% are printed that may differ depending on *why* we want to print them,
% such as whether the goal is to generate valid Mercury code or to print
% as much detail as possible for debugging, even if those details are
% not expressible in Mercury syntax.
%
% The second is the "output" type class. Many (though not all) of the
% procedures that output parts of the parse tree come in groups of three,
% where the three follow the pattern:
%
%   :- pred mercury_output_xyz(..., io::di, io::uo) is det.
%   :- func mercury_xyz_to_string(...) = string.
%   :- pred mercury_format_xyz(..., U::di, U::uo) is det <= output(U).
%
% In most cases, the first two simply forward all the work to the third.
% This is possible because both io.state and string are members of the
% "output" typeclass.
%
% For the mercury_output_xyz versions, going through a typeclass interface is
% (for now) a slight slowdown, but the time cost is still small compared to
% the cost of I/O itself.
%
% For the mercury_xyz_to_string versions, the cost is acceptable because
% (for now) we only create relatively small strings this way, e.g. strings that
% go into error messages. The typeclass instance for strings has a quadratic
% complexity in the number of strings being appended but a reasonably low
% constant factor. If we ever want to use these functions to create long
% strings (longer than a few lines), then we should use a typeclass
% instance implementation that represents the entity being converted to string
% as a list of strings that must be concatenated together at the end using
% string.append_list (probably after being un-reversed, so that you can
% represent appending to the string by consing onto the front of the list).
% The complexity of an implementation like that can be linear in the size
% of the string being built, although it will have a higher constant factor.
%
%---------------------------------------------------------------------------%

:- module parse_tree.parse_tree_out_info.
:- interface.

:- import_module libs.
:- import_module libs.globals.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_data_pragma.

:- import_module char.
:- import_module io.
:- import_module list.
:- import_module string.
:- import_module term.

%---------------------------------------------------------------------------%

:- type merc_out_info.

:- type maybe_qualified_item_names
    --->    unqualified_item_names
    ;       qualified_item_names.

:- type maybe_output_line_numbers
    --->    dont_output_line_numbers
    ;       do_output_line_numbers.

:- type output_lang
    --->    output_mercury
    ;       output_debug.

:- func init_debug_merc_out_info = merc_out_info.
:- func init_merc_out_info(globals, maybe_qualified_item_names, output_lang)
    = merc_out_info.
:- func merc_out_info_disable_line_numbers(merc_out_info) = merc_out_info.

:- func get_maybe_qualified_item_names(merc_out_info)
    = maybe_qualified_item_names.
:- func get_output_line_numbers(merc_out_info)
    = maybe_output_line_numbers.
:- func get_output_lang(merc_out_info)
    = output_lang.

:- pred maybe_output_line_number(merc_out_info::in, prog_context::in,
    io::di, io::uo) is det.

:- pred maybe_unqualify_sym_name(merc_out_info::in,
    sym_name::in, sym_name::out) is det.

%---------------------------------------------------------------------------%

:- typeclass output(U) where [
    pred add_string(string::in, U::di, U::uo) is det,
    pred add_strings(list(string)::in, U::di, U::uo) is det,
    pred add_char(char::in, U::di, U::uo) is det,
    pred add_int(int::in, U::di, U::uo) is det,
    pred add_uint(uint::in, U::di, U::uo) is det,
    % XXX FIXED SIZE INT
    pred add_int8(int::in, U::di, U::uo) is det,
    pred add_uint8(int::in, U::di, U::uo) is det,
    pred add_int16(int::in, U::di, U::uo) is det,
    pred add_uint16(int::in, U::di, U::uo) is det,
    pred add_int32(int::in, U::di, U::uo) is det,
    pred add_uint32(int::in, U::di, U::uo) is det,
    pred add_float(float::in, U::di, U::uo) is det,
    pred add_purity_prefix(purity::in, U::di, U::uo) is det,
    pred add_quoted_atom(string::in, U::di, U::uo) is det,
    pred add_quoted_string(string::in, U::di, U::uo) is det,
    pred add_constant(const::in, U::di, U::uo) is det,
    pred add_eval_method(eval_method::in, U::di, U::uo) is det,
    pred add_lambda_eval_method(lambda_eval_method::in, U::di, U::uo) is det,
    pred add_escaped_string(string::in, U::di, U::uo) is det,
    pred add_format(string::in, list(poly_type)::in, U::di, U::uo) is det,
    pred add_list(list(T)::in, string::in,
        pred(T, U, U)::in(pred(in, di, uo) is det), U::di, U::uo) is det
].

:- instance output(io.state).
:- instance output(string).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module libs.options.
:- import_module parse_tree.prog_out.

:- import_module bool.
:- import_module term_io.

%---------------------------------------------------------------------------%

:- type merc_out_info
    --->    merc_out_info(
                moi_qualify_item_names      :: maybe_qualified_item_names,
                moi_output_line_numbers     :: maybe_output_line_numbers,
                moi_output_lang             :: output_lang
            ).

init_debug_merc_out_info = Info :-
    Info = merc_out_info(qualified_item_names, dont_output_line_numbers,
        output_debug).

init_merc_out_info(Globals, MaybeQualifiedItemNames, Lang) = Info :-
    globals.lookup_bool_option(Globals, line_numbers, LineNumbersOpt),
    ( LineNumbersOpt = no, LineNumbers = dont_output_line_numbers
    ; LineNumbersOpt = yes, LineNumbers = do_output_line_numbers
    ),
    Info = merc_out_info(MaybeQualifiedItemNames, LineNumbers, Lang).

merc_out_info_disable_line_numbers(Info0) = Info :-
    Info = Info0 ^ moi_output_line_numbers := dont_output_line_numbers.

get_maybe_qualified_item_names(Info) = Info ^ moi_qualify_item_names.
get_output_line_numbers(Info) = Info ^ moi_output_line_numbers.
get_output_lang(Info) = Info ^ moi_output_lang.

%---------------------------------------------------------------------------%

maybe_output_line_number(Info, Context, !IO) :-
    LineNumbers = get_output_line_numbers(Info),
    (
        LineNumbers = do_output_line_numbers,
        io.write_string("\t% ", !IO),
        prog_out.write_context(Context, !IO),
        io.write_string("\n", !IO)
    ;
        LineNumbers = dont_output_line_numbers
    ).

maybe_unqualify_sym_name(Info, SymName, OutSymName) :-
    MaybeQualifiedItemNames = get_maybe_qualified_item_names(Info),
    (
        MaybeQualifiedItemNames = qualified_item_names,
        OutSymName = SymName
    ;
        MaybeQualifiedItemNames = unqualified_item_names,
        OutSymName = unqualified(unqualify_name(SymName))
    ).

%---------------------------------------------------------------------------%

:- instance output(io.state) where [
    pred(add_string/3) is io.write_string,
    pred(add_strings/3) is io.write_strings,
    pred(add_char/3) is io.write_char,
    pred(add_int/3) is io.write_int,
    pred(add_uint/3) is write_uint_literal,
    pred(add_int8/3) is io.write_int,
    pred(add_uint8/3) is io.write_int,
    pred(add_int16/3) is io.write_int,
    pred(add_uint16/3) is io.write_int,
    pred(add_int32/3) is io.write_int,
    pred(add_uint32/3) is io.write_int,
    pred(add_float/3) is io.write_float,
    pred(add_purity_prefix/3) is prog_out.write_purity_prefix,
    pred(add_quoted_atom/3) is term_io.quote_atom,
    pred(add_quoted_string/3) is term_io.quote_string,
    pred(add_constant/3) is term_io.write_constant,
    pred(add_eval_method/3) is write_eval_eval_method,
    pred(add_lambda_eval_method/3) is write_lambda_eval_method,
    pred(add_escaped_string/3) is term_io.write_escaped_string,
    pred(add_format/4) is io.format,
    pred(add_list/5) is io.write_list
].

:- instance output(string) where [
    pred(add_string/3) is output_string,
    pred(add_strings/3) is output_strings,
    pred(add_char/3) is output_char,
    pred(add_int/3) is output_int,
    pred(add_uint/3) is output_uint,
    pred(add_int8/3) is output_int8,
    pred(add_uint8/3) is output_uint8,
    pred(add_int16/3) is output_int16,
    pred(add_uint16/3) is output_uint16,
    pred(add_int32/3) is output_int32,
    pred(add_uint32/3) is output_uint32,
    pred(add_float/3) is output_float,
    pred(add_purity_prefix/3) is output_purity_prefix,
    pred(add_quoted_atom/3) is output_quoted_atom,
    pred(add_quoted_string/3) is output_quoted_string,
    pred(add_constant/3) is output_constant,
    pred(add_eval_method/3) is output_eval_eval_method,
    pred(add_lambda_eval_method/3) is output_lambda_eval_method,
    pred(add_escaped_string/3) is output_escaped_string,
    pred(add_format/4) is output_format,
    pred(add_list/5) is output_list
].

%---------------------------------------------------------------------------%

:- pred write_uint_literal(uint::in, io::di, io::uo) is det.

write_uint_literal(UInt, !IO) :-
    io.write_uint(UInt, !IO),
    io.write_char('u', !IO).

%---------------------------------------------------------------------------%

:- pred write_eval_eval_method(eval_method::in, io::di, io::uo) is det.

write_eval_eval_method(EvalMethod, !IO) :-
    output_eval_eval_method(EvalMethod, "", EvalMethodStr),
    io.write_string(EvalMethodStr, !IO).

:- pred write_lambda_eval_method(lambda_eval_method::in, io::di, io::uo)
    is det.

write_lambda_eval_method(LambdaEvalMethod, !IO) :-
    output_lambda_eval_method(LambdaEvalMethod, "", LambdaEvalMethodStr),
    io.write_string(LambdaEvalMethodStr, !IO).

%---------------------------------------------------------------------------%

:- pred output_string(string::in, string::di, string::uo) is det.

output_string(S, Str0, Str) :-
    string.append(Str0, S, Str).

:- pred output_strings(list(string)::in, string::di, string::uo) is det.

output_strings(Strs, Str0, Str) :-
    string.append_list([Str0 | Strs], Str).

:- pred output_char(char::in, string::di, string::uo) is det.

output_char(C, Str0, Str) :-
    string.char_to_string(C, S),
    string.append(Str0, S, Str).

:- pred output_int(int::in, string::di, string::uo) is det.

output_int(I, Str0, Str) :-
    string.int_to_string(I, S),
    string.append(Str0, S, Str).

:- pred output_uint(uint::in, string::di, string::uo) is det.

output_uint(U, Str0, Str) :-
    S = uint_to_string(U) ++ "u",
    string.append(Str0, S, Str).

% XXX FIXED SIZE INT
:- pred output_int8(int::in, string::di, string::uo) is det.

output_int8(I, Str0, Str) :-
    string.int_to_string(I, S),
    string.append(Str0, S, Str).

:- pred output_uint8(int::in, string::di, string::uo) is det.

output_uint8(I, Str0, Str) :-
    string.int_to_string(I, S),
    string.append(Str0, S, Str).

:- pred output_int16(int::in, string::di, string::uo) is det.

output_int16(I, Str0, Str) :-
    string.int_to_string(I, S),
    string.append(Str0, S, Str).

:- pred output_uint16(int::in, string::di, string::uo) is det.

output_uint16(I, Str0, Str) :-
    string.int_to_string(I, S),
    string.append(Str0, S, Str).

:- pred output_int32(int::in, string::di, string::uo) is det.

output_int32(I, Str0, Str) :-
    string.int_to_string(I, S),
    string.append(Str0, S, Str).

:- pred output_uint32(int::in, string::di, string::uo) is det.

output_uint32(I, Str0, Str) :-
    string.int_to_string(I, S),
    string.append(Str0, S, Str).

:- pred output_float(float::in, string::di, string::uo) is det.

output_float(F, Str0, Str) :-
    string.float_to_string(F, S),
    string.append(Str0, S, Str).

:- pred output_purity_prefix(purity::in, string::di, string::uo) is det.

output_purity_prefix(P, Str0, Str) :-
    S = purity_prefix_to_string(P),
    string.append(Str0, S, Str).

:- pred output_quoted_atom(string::in, string::di, string::uo) is det.

output_quoted_atom(A, Str0, Str) :-
    QA = term_io.quoted_atom(A),
    string.append(Str0, QA, Str).

:- pred output_quoted_string(string::in, string::di, string::uo) is det.

output_quoted_string(A, Str0, Str) :-
    QA = term_io.quoted_string(A),
    string.append(Str0, QA, Str).

:- pred output_constant(const::in, string::di, string::uo) is det.

output_constant(C, Str0, Str) :-
    CS = term_io.format_constant(C),
    string.append(Str0, CS, Str).

:- pred output_escaped_string(string::in, string::di, string::uo) is det.

output_escaped_string(S, Str0, Str) :-
    ES = term_io.escaped_string(S),
    string.append(Str0, ES, Str).

:- pred output_eval_eval_method(eval_method::in, string::di, string::uo)
    is det.

output_eval_eval_method(EvalMethod, !Str) :-
    output_string("eval_", !Str),
    output_string(eval_method_to_string(EvalMethod), !Str).

:- pred output_lambda_eval_method(lambda_eval_method::in,
    string::di, string::uo) is det.

output_lambda_eval_method(lambda_normal, !Str) :-
    output_string("normal", !Str).

:- pred output_format(string::in, list(poly_type)::in,
    string::di, string::uo) is det.

output_format(Format, Items, Str0, Str) :-
    S = string.format(Format, Items),
    string.append(Str0, S, Str).

:- pred output_list(list(T)::in, string::in,
    pred(T, string, string)::in(pred(in, di, uo) is det),
    string::di, string::uo) is det.

output_list([], _, _, !Str).
output_list([Item | Items], Sep, Pred, !Str) :-
    Pred(Item, !Str),
    (
        Items = []
    ;
        Items = [_ | _],
        output_string(Sep, !Str),
        output_list(Items, Sep, Pred, !Str)
    ).

%---------------------------------------------------------------------------%
:- end_module parse_tree.parse_tree_out_info.
%---------------------------------------------------------------------------%
