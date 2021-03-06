%---------------------------------------------------------------------------%
% vim: ts=4 sw=4 et ft=mercury
%---------------------------------------------------------------------------%

:- module time_yaowl.

:- interface.
:- import_module io.

:- type time_global(G).
:- type time_static(S)
    --->    time_static(S).
:- type time_token(T).
:- type time_state_holder(StateHolder).

:- type yaowl_specification(G, T)
    --->    yaowl_specification(
                G, T
            ).

:- typeclass yaowl_static_global_token(S, G, T) <= ((S -> G)) where [].

:- pred build_time_yaowl_specification(S::in,
    yaowl_specification(time_global(G), time_token(T))::out,
    io::di, io::uo) is det
    <= (yaowl_static_global_token(S, G, T)).

%---------------------------------------------------------------------------%

:- implementation.

:- import_module time.

build_time_yaowl_specification(S, WF, !IO) :-
    build_specification(time_static(S), WF, !IO).

:- instance yaowl_static_global_token(time_static(S), time_global(G),
    time_token(T)) <= yaowl_static_global_token(S, G, T) where [].

:- type time_global(G)
    --->    time_global(
                tg_global          :: G,
                tg_time            :: tm
            ).

:- type time_token(T)
    --->    time_token(
                tt_token           :: T,
                tt_time            :: time_t
            ).

:- type time_state_holder(StateHolder)
    --->    time_state_holder(StateHolder).

%---------------------------------------------------------------------------%

:- pred build_specification(S::in, yaowl_specification(G, T)::out,
    io::di, io::uo) is det <= (yaowl_static_global_token(S, G, T)).

:- pragma external_pred(build_specification/4).

:- pragma foreign_code("Java", "

    private static time_yaowl.Yaowl_specification_2
    build_specification_4_p_0(Object []a1, Object a2) {
        return null;
    }
").
