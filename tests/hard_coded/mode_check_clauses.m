:- module mode_check_clauses.

:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- import_module pair, solutions.

main(!IO) :-
	solutions(test02_base, Base02),
	solutions(test02_pragma, Pragma02),
	solutions(test11_base(1), Base11),
	solutions(test11_pragma(1), Pragma11),
	( Base02 = Pragma02 ->
		io__write_string("02 test works\n", !IO)
	;
		io__write_string("02 test doesn't work\n", !IO)
	),
	( Base11 = Pragma11 ->
		io__write_string("11 test works\n", !IO)
	;
		io__write_string("11 test doesn't work\n", !IO)
	).

:- pred test02_base(pair(int)::out) is multi.

test02_base(A - B) :-
	cycle500_base(A, B).

:- pred test11_base(int::in, int::out) is nondet.

test11_base(A, B) :-
	cycle500_base(A, B).

:- pred test02_pragma(pair(int)::out) is multi.

test02_pragma(A - B) :-
	cycle500_pragma(A, B).

:- pred test11_pragma(int::in, int::out) is nondet.

test11_pragma(A, B) :-
	cycle500_pragma(A, B).

:- pred cycle500_base(int, int).
:- mode cycle500_base(in, out) is semidet.
:- mode cycle500_base(out, out) is multi.

cycle500_base(0,1).
cycle500_base(1,2).
cycle500_base(2,3).
cycle500_base(3,4).
cycle500_base(4,5).
cycle500_base(5,6).
cycle500_base(6,7).
cycle500_base(7,8).
cycle500_base(8,9).
cycle500_base(9,10).
cycle500_base(10,11).
cycle500_base(11,12).
cycle500_base(12,13).
cycle500_base(13,14).
cycle500_base(14,15).
cycle500_base(15,16).
cycle500_base(16,17).
cycle500_base(17,18).
cycle500_base(18,19).
cycle500_base(19,20).
cycle500_base(20,21).
cycle500_base(21,22).
cycle500_base(22,23).
cycle500_base(23,24).
cycle500_base(24,25).
cycle500_base(25,26).
cycle500_base(26,27).
cycle500_base(27,28).
cycle500_base(28,29).
cycle500_base(29,30).
cycle500_base(30,31).
cycle500_base(31,32).
cycle500_base(32,33).
cycle500_base(33,34).
cycle500_base(34,35).
cycle500_base(35,36).
cycle500_base(36,37).
cycle500_base(37,38).
cycle500_base(38,39).
cycle500_base(39,40).
cycle500_base(40,41).
cycle500_base(41,42).
cycle500_base(42,43).
cycle500_base(43,44).
cycle500_base(44,45).
cycle500_base(45,46).
cycle500_base(46,47).
cycle500_base(47,48).
cycle500_base(48,49).
cycle500_base(49,50).
cycle500_base(50,51).
cycle500_base(51,52).
cycle500_base(52,53).
cycle500_base(53,54).
cycle500_base(54,55).
cycle500_base(55,56).
cycle500_base(56,57).
cycle500_base(57,58).
cycle500_base(58,59).
cycle500_base(59,60).
cycle500_base(60,61).
cycle500_base(61,62).
cycle500_base(62,63).
cycle500_base(63,64).
cycle500_base(64,65).
cycle500_base(65,66).
cycle500_base(66,67).
cycle500_base(67,68).
cycle500_base(68,69).
cycle500_base(69,70).
cycle500_base(70,71).
cycle500_base(71,72).
cycle500_base(72,73).
cycle500_base(73,74).
cycle500_base(74,75).
cycle500_base(75,76).
cycle500_base(76,77).
cycle500_base(77,78).
cycle500_base(78,79).
cycle500_base(79,80).
cycle500_base(80,81).
cycle500_base(81,82).
cycle500_base(82,83).
cycle500_base(83,84).
cycle500_base(84,85).
cycle500_base(85,86).
cycle500_base(86,87).
cycle500_base(87,88).
cycle500_base(88,89).
cycle500_base(89,90).
cycle500_base(90,91).
cycle500_base(91,92).
cycle500_base(92,93).
cycle500_base(93,94).
cycle500_base(94,95).
cycle500_base(95,96).
cycle500_base(96,97).
cycle500_base(97,98).
cycle500_base(98,99).
cycle500_base(99,100).
cycle500_base(100,101).
cycle500_base(101,102).
cycle500_base(102,103).
cycle500_base(103,104).
cycle500_base(104,105).
cycle500_base(105,106).
cycle500_base(106,107).
cycle500_base(107,108).
cycle500_base(108,109).
cycle500_base(109,110).
cycle500_base(110,111).
cycle500_base(111,112).
cycle500_base(112,113).
cycle500_base(113,114).
cycle500_base(114,115).
cycle500_base(115,116).
cycle500_base(116,117).
cycle500_base(117,118).
cycle500_base(118,119).
cycle500_base(119,120).
cycle500_base(120,121).
cycle500_base(121,122).
cycle500_base(122,123).
cycle500_base(123,124).
cycle500_base(124,125).
cycle500_base(125,126).
cycle500_base(126,127).
cycle500_base(127,128).
cycle500_base(128,129).
cycle500_base(129,130).
cycle500_base(130,131).
cycle500_base(131,132).
cycle500_base(132,133).
cycle500_base(133,134).
cycle500_base(134,135).
cycle500_base(135,136).
cycle500_base(136,137).
cycle500_base(137,138).
cycle500_base(138,139).
cycle500_base(139,140).
cycle500_base(140,141).
cycle500_base(141,142).
cycle500_base(142,143).
cycle500_base(143,144).
cycle500_base(144,145).
cycle500_base(145,146).
cycle500_base(146,147).
cycle500_base(147,148).
cycle500_base(148,149).
cycle500_base(149,150).
cycle500_base(150,151).
cycle500_base(151,152).
cycle500_base(152,153).
cycle500_base(153,154).
cycle500_base(154,155).
cycle500_base(155,156).
cycle500_base(156,157).
cycle500_base(157,158).
cycle500_base(158,159).
cycle500_base(159,160).
cycle500_base(160,161).
cycle500_base(161,162).
cycle500_base(162,163).
cycle500_base(163,164).
cycle500_base(164,165).
cycle500_base(165,166).
cycle500_base(166,167).
cycle500_base(167,168).
cycle500_base(168,169).
cycle500_base(169,170).
cycle500_base(170,171).
cycle500_base(171,172).
cycle500_base(172,173).
cycle500_base(173,174).
cycle500_base(174,175).
cycle500_base(175,176).
cycle500_base(176,177).
cycle500_base(177,178).
cycle500_base(178,179).
cycle500_base(179,180).
cycle500_base(180,181).
cycle500_base(181,182).
cycle500_base(182,183).
cycle500_base(183,184).
cycle500_base(184,185).
cycle500_base(185,186).
cycle500_base(186,187).
cycle500_base(187,188).
cycle500_base(188,189).
cycle500_base(189,190).
cycle500_base(190,191).
cycle500_base(191,192).
cycle500_base(192,193).
cycle500_base(193,194).
cycle500_base(194,195).
cycle500_base(195,196).
cycle500_base(196,197).
cycle500_base(197,198).
cycle500_base(198,199).
cycle500_base(199,200).
cycle500_base(200,201).
cycle500_base(201,202).
cycle500_base(202,203).
cycle500_base(203,204).
cycle500_base(204,205).
cycle500_base(205,206).
cycle500_base(206,207).
cycle500_base(207,208).
cycle500_base(208,209).
cycle500_base(209,210).
cycle500_base(210,211).
cycle500_base(211,212).
cycle500_base(212,213).
cycle500_base(213,214).
cycle500_base(214,215).
cycle500_base(215,216).
cycle500_base(216,217).
cycle500_base(217,218).
cycle500_base(218,219).
cycle500_base(219,220).
cycle500_base(220,221).
cycle500_base(221,222).
cycle500_base(222,223).
cycle500_base(223,224).
cycle500_base(224,225).
cycle500_base(225,226).
cycle500_base(226,227).
cycle500_base(227,228).
cycle500_base(228,229).
cycle500_base(229,230).
cycle500_base(230,231).
cycle500_base(231,232).
cycle500_base(232,233).
cycle500_base(233,234).
cycle500_base(234,235).
cycle500_base(235,236).
cycle500_base(236,237).
cycle500_base(237,238).
cycle500_base(238,239).
cycle500_base(239,240).
cycle500_base(240,241).
cycle500_base(241,242).
cycle500_base(242,243).
cycle500_base(243,244).
cycle500_base(244,245).
cycle500_base(245,246).
cycle500_base(246,247).
cycle500_base(247,248).
cycle500_base(248,249).
cycle500_base(249,250).
cycle500_base(250,251).
cycle500_base(251,252).
cycle500_base(252,253).
cycle500_base(253,254).
cycle500_base(254,255).
cycle500_base(255,256).
cycle500_base(256,257).
cycle500_base(257,258).
cycle500_base(258,259).
cycle500_base(259,260).
cycle500_base(260,261).
cycle500_base(261,262).
cycle500_base(262,263).
cycle500_base(263,264).
cycle500_base(264,265).
cycle500_base(265,266).
cycle500_base(266,267).
cycle500_base(267,268).
cycle500_base(268,269).
cycle500_base(269,270).
cycle500_base(270,271).
cycle500_base(271,272).
cycle500_base(272,273).
cycle500_base(273,274).
cycle500_base(274,275).
cycle500_base(275,276).
cycle500_base(276,277).
cycle500_base(277,278).
cycle500_base(278,279).
cycle500_base(279,280).
cycle500_base(280,281).
cycle500_base(281,282).
cycle500_base(282,283).
cycle500_base(283,284).
cycle500_base(284,285).
cycle500_base(285,286).
cycle500_base(286,287).
cycle500_base(287,288).
cycle500_base(288,289).
cycle500_base(289,290).
cycle500_base(290,291).
cycle500_base(291,292).
cycle500_base(292,293).
cycle500_base(293,294).
cycle500_base(294,295).
cycle500_base(295,296).
cycle500_base(296,297).
cycle500_base(297,298).
cycle500_base(298,299).
cycle500_base(299,300).
cycle500_base(300,301).
cycle500_base(301,302).
cycle500_base(302,303).
cycle500_base(303,304).
cycle500_base(304,305).
cycle500_base(305,306).
cycle500_base(306,307).
cycle500_base(307,308).
cycle500_base(308,309).
cycle500_base(309,310).
cycle500_base(310,311).
cycle500_base(311,312).
cycle500_base(312,313).
cycle500_base(313,314).
cycle500_base(314,315).
cycle500_base(315,316).
cycle500_base(316,317).
cycle500_base(317,318).
cycle500_base(318,319).
cycle500_base(319,320).
cycle500_base(320,321).
cycle500_base(321,322).
cycle500_base(322,323).
cycle500_base(323,324).
cycle500_base(324,325).
cycle500_base(325,326).
cycle500_base(326,327).
cycle500_base(327,328).
cycle500_base(328,329).
cycle500_base(329,330).
cycle500_base(330,331).
cycle500_base(331,332).
cycle500_base(332,333).
cycle500_base(333,334).
cycle500_base(334,335).
cycle500_base(335,336).
cycle500_base(336,337).
cycle500_base(337,338).
cycle500_base(338,339).
cycle500_base(339,340).
cycle500_base(340,341).
cycle500_base(341,342).
cycle500_base(342,343).
cycle500_base(343,344).
cycle500_base(344,345).
cycle500_base(345,346).
cycle500_base(346,347).
cycle500_base(347,348).
cycle500_base(348,349).
cycle500_base(349,350).
cycle500_base(350,351).
cycle500_base(351,352).
cycle500_base(352,353).
cycle500_base(353,354).
cycle500_base(354,355).
cycle500_base(355,356).
cycle500_base(356,357).
cycle500_base(357,358).
cycle500_base(358,359).
cycle500_base(359,360).
cycle500_base(360,361).
cycle500_base(361,362).
cycle500_base(362,363).
cycle500_base(363,364).
cycle500_base(364,365).
cycle500_base(365,366).
cycle500_base(366,367).
cycle500_base(367,368).
cycle500_base(368,369).
cycle500_base(369,370).
cycle500_base(370,371).
cycle500_base(371,372).
cycle500_base(372,373).
cycle500_base(373,374).
cycle500_base(374,375).
cycle500_base(375,376).
cycle500_base(376,377).
cycle500_base(377,378).
cycle500_base(378,379).
cycle500_base(379,380).
cycle500_base(380,381).
cycle500_base(381,382).
cycle500_base(382,383).
cycle500_base(383,384).
cycle500_base(384,385).
cycle500_base(385,386).
cycle500_base(386,387).
cycle500_base(387,388).
cycle500_base(388,389).
cycle500_base(389,390).
cycle500_base(390,391).
cycle500_base(391,392).
cycle500_base(392,393).
cycle500_base(393,394).
cycle500_base(394,395).
cycle500_base(395,396).
cycle500_base(396,397).
cycle500_base(397,398).
cycle500_base(398,399).
cycle500_base(399,400).
cycle500_base(400,401).
cycle500_base(401,402).
cycle500_base(402,403).
cycle500_base(403,404).
cycle500_base(404,405).
cycle500_base(405,406).
cycle500_base(406,407).
cycle500_base(407,408).
cycle500_base(408,409).
cycle500_base(409,410).
cycle500_base(410,411).
cycle500_base(411,412).
cycle500_base(412,413).
cycle500_base(413,414).
cycle500_base(414,415).
cycle500_base(415,416).
cycle500_base(416,417).
cycle500_base(417,418).
cycle500_base(418,419).
cycle500_base(419,420).
cycle500_base(420,421).
cycle500_base(421,422).
cycle500_base(422,423).
cycle500_base(423,424).
cycle500_base(424,425).
cycle500_base(425,426).
cycle500_base(426,427).
cycle500_base(427,428).
cycle500_base(428,429).
cycle500_base(429,430).
cycle500_base(430,431).
cycle500_base(431,432).
cycle500_base(432,433).
cycle500_base(433,434).
cycle500_base(434,435).
cycle500_base(435,436).
cycle500_base(436,437).
cycle500_base(437,438).
cycle500_base(438,439).
cycle500_base(439,440).
cycle500_base(440,441).
cycle500_base(441,442).
cycle500_base(442,443).
cycle500_base(443,444).
cycle500_base(444,445).
cycle500_base(445,446).
cycle500_base(446,447).
cycle500_base(447,448).
cycle500_base(448,449).
cycle500_base(449,450).
cycle500_base(450,451).
cycle500_base(451,452).
cycle500_base(452,453).
cycle500_base(453,454).
cycle500_base(454,455).
cycle500_base(455,456).
cycle500_base(456,457).
cycle500_base(457,458).
cycle500_base(458,459).
cycle500_base(459,460).
cycle500_base(460,461).
cycle500_base(461,462).
cycle500_base(462,463).
cycle500_base(463,464).
cycle500_base(464,465).
cycle500_base(465,466).
cycle500_base(466,467).
cycle500_base(467,468).
cycle500_base(468,469).
cycle500_base(469,470).
cycle500_base(470,471).
cycle500_base(471,472).
cycle500_base(472,473).
cycle500_base(473,474).
cycle500_base(474,475).
cycle500_base(475,476).
cycle500_base(476,477).
cycle500_base(477,478).
cycle500_base(478,479).
cycle500_base(479,480).
cycle500_base(480,481).
cycle500_base(481,482).
cycle500_base(482,483).
cycle500_base(483,484).
cycle500_base(484,485).
cycle500_base(485,486).
cycle500_base(486,487).
cycle500_base(487,488).
cycle500_base(488,489).
cycle500_base(489,490).
cycle500_base(490,491).
cycle500_base(491,492).
cycle500_base(492,493).
cycle500_base(493,494).
cycle500_base(494,495).
cycle500_base(495,496).
cycle500_base(496,497).
cycle500_base(497,498).
cycle500_base(498,499).
cycle500_base(499,500).
cycle500_base(500,0).

:- pred cycle500_pragma(int, int).
:- mode cycle500_pragma(in, out) is semidet.
:- mode cycle500_pragma(out, out) is multi.

:- pragma mode_check_clauses(cycle500_pragma/2).

cycle500_pragma(0,1).
cycle500_pragma(1,2).
cycle500_pragma(2,3).
cycle500_pragma(3,4).
cycle500_pragma(4,5).
cycle500_pragma(5,6).
cycle500_pragma(6,7).
cycle500_pragma(7,8).
cycle500_pragma(8,9).
cycle500_pragma(9,10).
cycle500_pragma(10,11).
cycle500_pragma(11,12).
cycle500_pragma(12,13).
cycle500_pragma(13,14).
cycle500_pragma(14,15).
cycle500_pragma(15,16).
cycle500_pragma(16,17).
cycle500_pragma(17,18).
cycle500_pragma(18,19).
cycle500_pragma(19,20).
cycle500_pragma(20,21).
cycle500_pragma(21,22).
cycle500_pragma(22,23).
cycle500_pragma(23,24).
cycle500_pragma(24,25).
cycle500_pragma(25,26).
cycle500_pragma(26,27).
cycle500_pragma(27,28).
cycle500_pragma(28,29).
cycle500_pragma(29,30).
cycle500_pragma(30,31).
cycle500_pragma(31,32).
cycle500_pragma(32,33).
cycle500_pragma(33,34).
cycle500_pragma(34,35).
cycle500_pragma(35,36).
cycle500_pragma(36,37).
cycle500_pragma(37,38).
cycle500_pragma(38,39).
cycle500_pragma(39,40).
cycle500_pragma(40,41).
cycle500_pragma(41,42).
cycle500_pragma(42,43).
cycle500_pragma(43,44).
cycle500_pragma(44,45).
cycle500_pragma(45,46).
cycle500_pragma(46,47).
cycle500_pragma(47,48).
cycle500_pragma(48,49).
cycle500_pragma(49,50).
cycle500_pragma(50,51).
cycle500_pragma(51,52).
cycle500_pragma(52,53).
cycle500_pragma(53,54).
cycle500_pragma(54,55).
cycle500_pragma(55,56).
cycle500_pragma(56,57).
cycle500_pragma(57,58).
cycle500_pragma(58,59).
cycle500_pragma(59,60).
cycle500_pragma(60,61).
cycle500_pragma(61,62).
cycle500_pragma(62,63).
cycle500_pragma(63,64).
cycle500_pragma(64,65).
cycle500_pragma(65,66).
cycle500_pragma(66,67).
cycle500_pragma(67,68).
cycle500_pragma(68,69).
cycle500_pragma(69,70).
cycle500_pragma(70,71).
cycle500_pragma(71,72).
cycle500_pragma(72,73).
cycle500_pragma(73,74).
cycle500_pragma(74,75).
cycle500_pragma(75,76).
cycle500_pragma(76,77).
cycle500_pragma(77,78).
cycle500_pragma(78,79).
cycle500_pragma(79,80).
cycle500_pragma(80,81).
cycle500_pragma(81,82).
cycle500_pragma(82,83).
cycle500_pragma(83,84).
cycle500_pragma(84,85).
cycle500_pragma(85,86).
cycle500_pragma(86,87).
cycle500_pragma(87,88).
cycle500_pragma(88,89).
cycle500_pragma(89,90).
cycle500_pragma(90,91).
cycle500_pragma(91,92).
cycle500_pragma(92,93).
cycle500_pragma(93,94).
cycle500_pragma(94,95).
cycle500_pragma(95,96).
cycle500_pragma(96,97).
cycle500_pragma(97,98).
cycle500_pragma(98,99).
cycle500_pragma(99,100).
cycle500_pragma(100,101).
cycle500_pragma(101,102).
cycle500_pragma(102,103).
cycle500_pragma(103,104).
cycle500_pragma(104,105).
cycle500_pragma(105,106).
cycle500_pragma(106,107).
cycle500_pragma(107,108).
cycle500_pragma(108,109).
cycle500_pragma(109,110).
cycle500_pragma(110,111).
cycle500_pragma(111,112).
cycle500_pragma(112,113).
cycle500_pragma(113,114).
cycle500_pragma(114,115).
cycle500_pragma(115,116).
cycle500_pragma(116,117).
cycle500_pragma(117,118).
cycle500_pragma(118,119).
cycle500_pragma(119,120).
cycle500_pragma(120,121).
cycle500_pragma(121,122).
cycle500_pragma(122,123).
cycle500_pragma(123,124).
cycle500_pragma(124,125).
cycle500_pragma(125,126).
cycle500_pragma(126,127).
cycle500_pragma(127,128).
cycle500_pragma(128,129).
cycle500_pragma(129,130).
cycle500_pragma(130,131).
cycle500_pragma(131,132).
cycle500_pragma(132,133).
cycle500_pragma(133,134).
cycle500_pragma(134,135).
cycle500_pragma(135,136).
cycle500_pragma(136,137).
cycle500_pragma(137,138).
cycle500_pragma(138,139).
cycle500_pragma(139,140).
cycle500_pragma(140,141).
cycle500_pragma(141,142).
cycle500_pragma(142,143).
cycle500_pragma(143,144).
cycle500_pragma(144,145).
cycle500_pragma(145,146).
cycle500_pragma(146,147).
cycle500_pragma(147,148).
cycle500_pragma(148,149).
cycle500_pragma(149,150).
cycle500_pragma(150,151).
cycle500_pragma(151,152).
cycle500_pragma(152,153).
cycle500_pragma(153,154).
cycle500_pragma(154,155).
cycle500_pragma(155,156).
cycle500_pragma(156,157).
cycle500_pragma(157,158).
cycle500_pragma(158,159).
cycle500_pragma(159,160).
cycle500_pragma(160,161).
cycle500_pragma(161,162).
cycle500_pragma(162,163).
cycle500_pragma(163,164).
cycle500_pragma(164,165).
cycle500_pragma(165,166).
cycle500_pragma(166,167).
cycle500_pragma(167,168).
cycle500_pragma(168,169).
cycle500_pragma(169,170).
cycle500_pragma(170,171).
cycle500_pragma(171,172).
cycle500_pragma(172,173).
cycle500_pragma(173,174).
cycle500_pragma(174,175).
cycle500_pragma(175,176).
cycle500_pragma(176,177).
cycle500_pragma(177,178).
cycle500_pragma(178,179).
cycle500_pragma(179,180).
cycle500_pragma(180,181).
cycle500_pragma(181,182).
cycle500_pragma(182,183).
cycle500_pragma(183,184).
cycle500_pragma(184,185).
cycle500_pragma(185,186).
cycle500_pragma(186,187).
cycle500_pragma(187,188).
cycle500_pragma(188,189).
cycle500_pragma(189,190).
cycle500_pragma(190,191).
cycle500_pragma(191,192).
cycle500_pragma(192,193).
cycle500_pragma(193,194).
cycle500_pragma(194,195).
cycle500_pragma(195,196).
cycle500_pragma(196,197).
cycle500_pragma(197,198).
cycle500_pragma(198,199).
cycle500_pragma(199,200).
cycle500_pragma(200,201).
cycle500_pragma(201,202).
cycle500_pragma(202,203).
cycle500_pragma(203,204).
cycle500_pragma(204,205).
cycle500_pragma(205,206).
cycle500_pragma(206,207).
cycle500_pragma(207,208).
cycle500_pragma(208,209).
cycle500_pragma(209,210).
cycle500_pragma(210,211).
cycle500_pragma(211,212).
cycle500_pragma(212,213).
cycle500_pragma(213,214).
cycle500_pragma(214,215).
cycle500_pragma(215,216).
cycle500_pragma(216,217).
cycle500_pragma(217,218).
cycle500_pragma(218,219).
cycle500_pragma(219,220).
cycle500_pragma(220,221).
cycle500_pragma(221,222).
cycle500_pragma(222,223).
cycle500_pragma(223,224).
cycle500_pragma(224,225).
cycle500_pragma(225,226).
cycle500_pragma(226,227).
cycle500_pragma(227,228).
cycle500_pragma(228,229).
cycle500_pragma(229,230).
cycle500_pragma(230,231).
cycle500_pragma(231,232).
cycle500_pragma(232,233).
cycle500_pragma(233,234).
cycle500_pragma(234,235).
cycle500_pragma(235,236).
cycle500_pragma(236,237).
cycle500_pragma(237,238).
cycle500_pragma(238,239).
cycle500_pragma(239,240).
cycle500_pragma(240,241).
cycle500_pragma(241,242).
cycle500_pragma(242,243).
cycle500_pragma(243,244).
cycle500_pragma(244,245).
cycle500_pragma(245,246).
cycle500_pragma(246,247).
cycle500_pragma(247,248).
cycle500_pragma(248,249).
cycle500_pragma(249,250).
cycle500_pragma(250,251).
cycle500_pragma(251,252).
cycle500_pragma(252,253).
cycle500_pragma(253,254).
cycle500_pragma(254,255).
cycle500_pragma(255,256).
cycle500_pragma(256,257).
cycle500_pragma(257,258).
cycle500_pragma(258,259).
cycle500_pragma(259,260).
cycle500_pragma(260,261).
cycle500_pragma(261,262).
cycle500_pragma(262,263).
cycle500_pragma(263,264).
cycle500_pragma(264,265).
cycle500_pragma(265,266).
cycle500_pragma(266,267).
cycle500_pragma(267,268).
cycle500_pragma(268,269).
cycle500_pragma(269,270).
cycle500_pragma(270,271).
cycle500_pragma(271,272).
cycle500_pragma(272,273).
cycle500_pragma(273,274).
cycle500_pragma(274,275).
cycle500_pragma(275,276).
cycle500_pragma(276,277).
cycle500_pragma(277,278).
cycle500_pragma(278,279).
cycle500_pragma(279,280).
cycle500_pragma(280,281).
cycle500_pragma(281,282).
cycle500_pragma(282,283).
cycle500_pragma(283,284).
cycle500_pragma(284,285).
cycle500_pragma(285,286).
cycle500_pragma(286,287).
cycle500_pragma(287,288).
cycle500_pragma(288,289).
cycle500_pragma(289,290).
cycle500_pragma(290,291).
cycle500_pragma(291,292).
cycle500_pragma(292,293).
cycle500_pragma(293,294).
cycle500_pragma(294,295).
cycle500_pragma(295,296).
cycle500_pragma(296,297).
cycle500_pragma(297,298).
cycle500_pragma(298,299).
cycle500_pragma(299,300).
cycle500_pragma(300,301).
cycle500_pragma(301,302).
cycle500_pragma(302,303).
cycle500_pragma(303,304).
cycle500_pragma(304,305).
cycle500_pragma(305,306).
cycle500_pragma(306,307).
cycle500_pragma(307,308).
cycle500_pragma(308,309).
cycle500_pragma(309,310).
cycle500_pragma(310,311).
cycle500_pragma(311,312).
cycle500_pragma(312,313).
cycle500_pragma(313,314).
cycle500_pragma(314,315).
cycle500_pragma(315,316).
cycle500_pragma(316,317).
cycle500_pragma(317,318).
cycle500_pragma(318,319).
cycle500_pragma(319,320).
cycle500_pragma(320,321).
cycle500_pragma(321,322).
cycle500_pragma(322,323).
cycle500_pragma(323,324).
cycle500_pragma(324,325).
cycle500_pragma(325,326).
cycle500_pragma(326,327).
cycle500_pragma(327,328).
cycle500_pragma(328,329).
cycle500_pragma(329,330).
cycle500_pragma(330,331).
cycle500_pragma(331,332).
cycle500_pragma(332,333).
cycle500_pragma(333,334).
cycle500_pragma(334,335).
cycle500_pragma(335,336).
cycle500_pragma(336,337).
cycle500_pragma(337,338).
cycle500_pragma(338,339).
cycle500_pragma(339,340).
cycle500_pragma(340,341).
cycle500_pragma(341,342).
cycle500_pragma(342,343).
cycle500_pragma(343,344).
cycle500_pragma(344,345).
cycle500_pragma(345,346).
cycle500_pragma(346,347).
cycle500_pragma(347,348).
cycle500_pragma(348,349).
cycle500_pragma(349,350).
cycle500_pragma(350,351).
cycle500_pragma(351,352).
cycle500_pragma(352,353).
cycle500_pragma(353,354).
cycle500_pragma(354,355).
cycle500_pragma(355,356).
cycle500_pragma(356,357).
cycle500_pragma(357,358).
cycle500_pragma(358,359).
cycle500_pragma(359,360).
cycle500_pragma(360,361).
cycle500_pragma(361,362).
cycle500_pragma(362,363).
cycle500_pragma(363,364).
cycle500_pragma(364,365).
cycle500_pragma(365,366).
cycle500_pragma(366,367).
cycle500_pragma(367,368).
cycle500_pragma(368,369).
cycle500_pragma(369,370).
cycle500_pragma(370,371).
cycle500_pragma(371,372).
cycle500_pragma(372,373).
cycle500_pragma(373,374).
cycle500_pragma(374,375).
cycle500_pragma(375,376).
cycle500_pragma(376,377).
cycle500_pragma(377,378).
cycle500_pragma(378,379).
cycle500_pragma(379,380).
cycle500_pragma(380,381).
cycle500_pragma(381,382).
cycle500_pragma(382,383).
cycle500_pragma(383,384).
cycle500_pragma(384,385).
cycle500_pragma(385,386).
cycle500_pragma(386,387).
cycle500_pragma(387,388).
cycle500_pragma(388,389).
cycle500_pragma(389,390).
cycle500_pragma(390,391).
cycle500_pragma(391,392).
cycle500_pragma(392,393).
cycle500_pragma(393,394).
cycle500_pragma(394,395).
cycle500_pragma(395,396).
cycle500_pragma(396,397).
cycle500_pragma(397,398).
cycle500_pragma(398,399).
cycle500_pragma(399,400).
cycle500_pragma(400,401).
cycle500_pragma(401,402).
cycle500_pragma(402,403).
cycle500_pragma(403,404).
cycle500_pragma(404,405).
cycle500_pragma(405,406).
cycle500_pragma(406,407).
cycle500_pragma(407,408).
cycle500_pragma(408,409).
cycle500_pragma(409,410).
cycle500_pragma(410,411).
cycle500_pragma(411,412).
cycle500_pragma(412,413).
cycle500_pragma(413,414).
cycle500_pragma(414,415).
cycle500_pragma(415,416).
cycle500_pragma(416,417).
cycle500_pragma(417,418).
cycle500_pragma(418,419).
cycle500_pragma(419,420).
cycle500_pragma(420,421).
cycle500_pragma(421,422).
cycle500_pragma(422,423).
cycle500_pragma(423,424).
cycle500_pragma(424,425).
cycle500_pragma(425,426).
cycle500_pragma(426,427).
cycle500_pragma(427,428).
cycle500_pragma(428,429).
cycle500_pragma(429,430).
cycle500_pragma(430,431).
cycle500_pragma(431,432).
cycle500_pragma(432,433).
cycle500_pragma(433,434).
cycle500_pragma(434,435).
cycle500_pragma(435,436).
cycle500_pragma(436,437).
cycle500_pragma(437,438).
cycle500_pragma(438,439).
cycle500_pragma(439,440).
cycle500_pragma(440,441).
cycle500_pragma(441,442).
cycle500_pragma(442,443).
cycle500_pragma(443,444).
cycle500_pragma(444,445).
cycle500_pragma(445,446).
cycle500_pragma(446,447).
cycle500_pragma(447,448).
cycle500_pragma(448,449).
cycle500_pragma(449,450).
cycle500_pragma(450,451).
cycle500_pragma(451,452).
cycle500_pragma(452,453).
cycle500_pragma(453,454).
cycle500_pragma(454,455).
cycle500_pragma(455,456).
cycle500_pragma(456,457).
cycle500_pragma(457,458).
cycle500_pragma(458,459).
cycle500_pragma(459,460).
cycle500_pragma(460,461).
cycle500_pragma(461,462).
cycle500_pragma(462,463).
cycle500_pragma(463,464).
cycle500_pragma(464,465).
cycle500_pragma(465,466).
cycle500_pragma(466,467).
cycle500_pragma(467,468).
cycle500_pragma(468,469).
cycle500_pragma(469,470).
cycle500_pragma(470,471).
cycle500_pragma(471,472).
cycle500_pragma(472,473).
cycle500_pragma(473,474).
cycle500_pragma(474,475).
cycle500_pragma(475,476).
cycle500_pragma(476,477).
cycle500_pragma(477,478).
cycle500_pragma(478,479).
cycle500_pragma(479,480).
cycle500_pragma(480,481).
cycle500_pragma(481,482).
cycle500_pragma(482,483).
cycle500_pragma(483,484).
cycle500_pragma(484,485).
cycle500_pragma(485,486).
cycle500_pragma(486,487).
cycle500_pragma(487,488).
cycle500_pragma(488,489).
cycle500_pragma(489,490).
cycle500_pragma(490,491).
cycle500_pragma(491,492).
cycle500_pragma(492,493).
cycle500_pragma(493,494).
cycle500_pragma(494,495).
cycle500_pragma(495,496).
cycle500_pragma(496,497).
cycle500_pragma(497,498).
cycle500_pragma(498,499).
cycle500_pragma(499,500).
cycle500_pragma(500,0).