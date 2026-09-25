// Auto-generated (25.09.2026 - 22:28) from the Code Page Identifiers table.
// Source: https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers
// Do not edit by hand -- regenerate with codepage_to_zig.py instead.

pub const CODEPAGE = enum(u32) {
    /// IBM EBCDIC US-Canada
    IBM037 = 37,
    /// OEM United States
    IBM437 = 437,
    /// IBM EBCDIC International
    IBM500 = 500,
    /// Arabic (ASMO 708)
    @"ASMO-708" = 708,
    /// Arabic (ASMO-449+, BCON V4)
    @"Arabic (ASMO-449+, BCON V4)" = 709,
    /// Arabic - Transparent Arabic
    @"Arabic - Transparent Arabic" = 710,
    /// Arabic (Transparent ASMO); Arabic (DOS)
    @"DOS-720" = 720,
    /// OEM Greek (formerly 437G); Greek (DOS)
    ibm737 = 737,
    /// OEM Baltic; Baltic (DOS)
    ibm775 = 775,
    /// OEM Multilingual Latin 1; Western European (DOS)
    ibm850 = 850,
    /// OEM Latin 2; Central European (DOS)
    ibm852 = 852,
    /// OEM Cyrillic (primarily Russian)
    IBM855 = 855,
    /// OEM Turkish; Turkish (DOS)
    ibm857 = 857,
    /// OEM Multilingual Latin 1 + Euro symbol
    IBM00858 = 858,
    /// OEM Portuguese; Portuguese (DOS)
    IBM860 = 860,
    /// OEM Icelandic; Icelandic (DOS)
    ibm861 = 861,
    /// OEM Hebrew; Hebrew (DOS)
    @"DOS-862" = 862,
    /// OEM French Canadian; French Canadian (DOS)
    IBM863 = 863,
    /// OEM Arabic; Arabic (864)
    IBM864 = 864,
    /// OEM Nordic; Nordic (DOS)
    IBM865 = 865,
    /// OEM Russian; Cyrillic (DOS)
    cp866 = 866,
    /// OEM Modern Greek; Greek, Modern (DOS)
    ibm869 = 869,
    /// IBM EBCDIC Multilingual/ROECE (Latin 2); IBM EBCDIC Multilingual Latin 2
    IBM870 = 870,
    /// Thai (Windows)
    @"windows-874" = 874,
    /// IBM EBCDIC Greek Modern
    cp875 = 875,
    /// ANSI/OEM Japanese; Japanese (Shift-JIS)
    shift_jis = 932,
    /// ANSI/OEM Simplified Chinese (PRC, Singapore); Chinese Simplified (GB2312)
    gb2312 = 936,
    /// ANSI/OEM Korean (Unified Hangul Code)
    @"ks_c_5601-1987" = 949,
    /// ANSI/OEM Traditional Chinese (Taiwan; Hong Kong SAR, PRC); Chinese Traditional (Big5)
    big5 = 950,
    /// IBM EBCDIC Turkish (Latin 5)
    IBM1026 = 1026,
    /// IBM EBCDIC Latin 1/Open System
    IBM01047 = 1047,
    /// IBM EBCDIC US-Canada (037 + Euro symbol); IBM EBCDIC (US-Canada-Euro)
    IBM01140 = 1140,
    /// IBM EBCDIC Germany (20273 + Euro symbol); IBM EBCDIC (Germany-Euro)
    IBM01141 = 1141,
    /// IBM EBCDIC Denmark-Norway (20277 + Euro symbol); IBM EBCDIC (Denmark-Norway-Euro)
    IBM01142 = 1142,
    /// IBM EBCDIC Finland-Sweden (20278 + Euro symbol); IBM EBCDIC (Finland-Sweden-Euro)
    IBM01143 = 1143,
    /// IBM EBCDIC Italy (20280 + Euro symbol); IBM EBCDIC (Italy-Euro)
    IBM01144 = 1144,
    /// IBM EBCDIC Latin America-Spain (20284 + Euro symbol); IBM EBCDIC (Spain-Euro)
    IBM01145 = 1145,
    /// IBM EBCDIC United Kingdom (20285 + Euro symbol); IBM EBCDIC (UK-Euro)
    IBM01146 = 1146,
    /// IBM EBCDIC France (20297 + Euro symbol); IBM EBCDIC (France-Euro)
    IBM01147 = 1147,
    /// IBM EBCDIC International (500 + Euro symbol); IBM EBCDIC (International-Euro)
    IBM01148 = 1148,
    /// IBM EBCDIC Icelandic (20871 + Euro symbol); IBM EBCDIC (Icelandic-Euro)
    IBM01149 = 1149,
    /// Unicode UTF-16, little endian byte order (BMP of ISO 10646); available only to managed applications
    @"utf-16" = 1200,
    /// Unicode UTF-16, big endian byte order; available only to managed applications
    unicodeFFFE = 1201,
    /// ANSI Central European; Central European (Windows)
    @"windows-1250" = 1250,
    /// ANSI Cyrillic; Cyrillic (Windows)
    @"windows-1251" = 1251,
    /// ANSI Latin 1; Western European (Windows)
    @"windows-1252" = 1252,
    /// ANSI Greek; Greek (Windows)
    @"windows-1253" = 1253,
    /// ANSI Turkish; Turkish (Windows)
    @"windows-1254" = 1254,
    /// ANSI Hebrew; Hebrew (Windows)
    @"windows-1255" = 1255,
    /// ANSI Arabic; Arabic (Windows)
    @"windows-1256" = 1256,
    /// ANSI Baltic; Baltic (Windows)
    @"windows-1257" = 1257,
    /// ANSI/OEM Vietnamese; Vietnamese (Windows)
    @"windows-1258" = 1258,
    /// Korean (Johab)
    Johab = 1361,
    /// MAC Roman; Western European (Mac)
    macintosh = 10000,
    /// Japanese (Mac)
    @"x-mac-japanese" = 10001,
    /// MAC Traditional Chinese (Big5); Chinese Traditional (Mac)
    @"x-mac-chinesetrad" = 10002,
    /// Korean (Mac)
    @"x-mac-korean" = 10003,
    /// Arabic (Mac)
    @"x-mac-arabic" = 10004,
    /// Hebrew (Mac)
    @"x-mac-hebrew" = 10005,
    /// Greek (Mac)
    @"x-mac-greek" = 10006,
    /// Cyrillic (Mac)
    @"x-mac-cyrillic" = 10007,
    /// MAC Simplified Chinese (GB 2312); Chinese Simplified (Mac)
    @"x-mac-chinesesimp" = 10008,
    /// Romanian (Mac)
    @"x-mac-romanian" = 10010,
    /// Ukrainian (Mac)
    @"x-mac-ukrainian" = 10017,
    /// Thai (Mac)
    @"x-mac-thai" = 10021,
    /// MAC Latin 2; Central European (Mac)
    @"x-mac-ce" = 10029,
    /// Icelandic (Mac)
    @"x-mac-icelandic" = 10079,
    /// Turkish (Mac)
    @"x-mac-turkish" = 10081,
    /// Croatian (Mac)
    @"x-mac-croatian" = 10082,
    /// Unicode UTF-32, little endian byte order; available only to managed applications
    @"utf-32" = 12000,
    /// Unicode UTF-32, big endian byte order; available only to managed applications
    @"utf-32BE" = 12001,
    /// CNS Taiwan; Chinese Traditional (CNS)
    @"x-Chinese_CNS" = 20000,
    /// TCA Taiwan
    @"x-cp20001" = 20001,
    /// Eten Taiwan; Chinese Traditional (Eten)
    @"x_Chinese-Eten" = 20002,
    /// IBM5550 Taiwan
    @"x-cp20003" = 20003,
    /// TeleText Taiwan
    @"x-cp20004" = 20004,
    /// Wang Taiwan
    @"x-cp20005" = 20005,
    /// IA5 (IRV International Alphabet No. 5, 7-bit); Western European (IA5)
    @"x-IA5" = 20105,
    /// IA5 German (7-bit)
    @"x-IA5-German" = 20106,
    /// IA5 Swedish (7-bit)
    @"x-IA5-Swedish" = 20107,
    /// IA5 Norwegian (7-bit)
    @"x-IA5-Norwegian" = 20108,
    /// US-ASCII (7-bit)
    @"us-ascii" = 20127,
    /// T.61
    @"x-cp20261" = 20261,
    /// ISO 6937 Non-Spacing Accent
    @"x-cp20269" = 20269,
    /// IBM EBCDIC Germany
    IBM273 = 20273,
    /// IBM EBCDIC Denmark-Norway
    IBM277 = 20277,
    /// IBM EBCDIC Finland-Sweden
    IBM278 = 20278,
    /// IBM EBCDIC Italy
    IBM280 = 20280,
    /// IBM EBCDIC Latin America-Spain
    IBM284 = 20284,
    /// IBM EBCDIC United Kingdom
    IBM285 = 20285,
    /// IBM EBCDIC Japanese Katakana Extended
    IBM290 = 20290,
    /// IBM EBCDIC France
    IBM297 = 20297,
    /// IBM EBCDIC Arabic
    IBM420 = 20420,
    /// IBM EBCDIC Greek
    IBM423 = 20423,
    /// IBM EBCDIC Hebrew
    IBM424 = 20424,
    /// IBM EBCDIC Korean Extended
    @"x-EBCDIC-KoreanExtended" = 20833,
    /// IBM EBCDIC Thai
    @"IBM-Thai" = 20838,
    /// Russian (KOI8-R); Cyrillic (KOI8-R)
    @"koi8-r" = 20866,
    /// IBM EBCDIC Icelandic
    IBM871 = 20871,
    /// IBM EBCDIC Cyrillic Russian
    IBM880 = 20880,
    /// IBM EBCDIC Turkish
    IBM905 = 20905,
    /// IBM EBCDIC Latin 1/Open System (1047 + Euro symbol)
    IBM00924 = 20924,
    /// Japanese (JIS 0208-1990 and 0212-1990)
    @"EUC-JP" = 20932,
    /// Simplified Chinese (GB2312); Chinese Simplified (GB2312-80)
    @"x-cp20936" = 20936,
    /// Korean Wansung
    @"x-cp20949" = 20949,
    /// IBM EBCDIC Cyrillic Serbian-Bulgarian
    cp1025 = 21025,
    /// (deprecated)
    @"(deprecated)" = 21027,
    /// Ukrainian (KOI8-U); Cyrillic (KOI8-U)
    @"koi8-u" = 21866,
    /// ISO 8859-1 Latin 1; Western European (ISO)
    @"iso-8859-1" = 28591,
    /// ISO 8859-2 Central European; Central European (ISO)
    @"iso-8859-2" = 28592,
    /// ISO 8859-3 Latin 3
    @"iso-8859-3" = 28593,
    /// ISO 8859-4 Baltic
    @"iso-8859-4" = 28594,
    /// ISO 8859-5 Cyrillic
    @"iso-8859-5" = 28595,
    /// ISO 8859-6 Arabic
    @"iso-8859-6" = 28596,
    /// ISO 8859-7 Greek
    @"iso-8859-7" = 28597,
    /// ISO 8859-8 Hebrew; Hebrew (ISO-Visual)
    @"iso-8859-8" = 28598,
    /// ISO 8859-9 Turkish
    @"iso-8859-9" = 28599,
    /// ISO 8859-13 Estonian
    @"iso-8859-13" = 28603,
    /// ISO 8859-15 Latin 9
    @"iso-8859-15" = 28605,
    /// Europa 3
    @"x-Europa" = 29001,
    /// ISO 8859-8 Hebrew; Hebrew (ISO-Logical)
    @"iso-8859-8-i" = 38598,
    /// ISO 2022 Japanese with no halfwidth Katakana; Japanese (JIS)
    @"iso-2022-jp" = 50220,
    /// ISO 2022 Japanese with halfwidth Katakana; Japanese (JIS-Allow 1 byte Kana)
    csISO2022JP = 50221,
    /// ISO 2022 Japanese JIS X 0201-1989; Japanese (JIS-Allow 1 byte Kana - SO/SI)
    @"iso-2022-jp (50222)" = 50222,
    /// ISO 2022 Korean
    @"iso-2022-kr" = 50225,
    /// ISO 2022 Simplified Chinese; Chinese Simplified (ISO 2022)
    @"x-cp50227" = 50227,
    /// ISO 2022 Traditional Chinese
    @"ISO 2022 Traditional Chinese" = 50229,
    /// EBCDIC Japanese (Katakana) Extended
    @"EBCDIC Japanese (Katakana) Extended" = 50930,
    /// EBCDIC US-Canada and Japanese
    @"EBCDIC US-Canada and Japanese" = 50931,
    /// EBCDIC Korean Extended and Korean
    @"EBCDIC Korean Extended and Korean" = 50933,
    /// EBCDIC Simplified Chinese Extended and Simplified Chinese
    @"EBCDIC Simplified Chinese Extended and Simplified Chinese" = 50935,
    /// EBCDIC Simplified Chinese
    @"EBCDIC Simplified Chinese" = 50936,
    /// EBCDIC US-Canada and Traditional Chinese
    @"EBCDIC US-Canada and Traditional Chinese" = 50937,
    /// EBCDIC Japanese (Latin) Extended and Japanese
    @"EBCDIC Japanese (Latin) Extended and Japanese" = 50939,
    /// EUC Japanese
    @"euc-jp" = 51932,
    /// EUC Simplified Chinese; Chinese Simplified (EUC)
    @"EUC-CN" = 51936,
    /// EUC Korean
    @"euc-kr" = 51949,
    /// EUC Traditional Chinese
    @"EUC Traditional Chinese" = 51950,
    /// HZ-GB2312 Simplified Chinese; Chinese Simplified (HZ)
    @"hz-gb-2312" = 52936,
    /// Windows XP and later: GB18030 Simplified Chinese (4 byte); Chinese Simplified (GB18030)
    GB18030 = 54936,
    /// ISCII Devanagari
    @"x-iscii-de" = 57002,
    /// ISCII Bangla
    @"x-iscii-be" = 57003,
    /// ISCII Tamil
    @"x-iscii-ta" = 57004,
    /// ISCII Telugu
    @"x-iscii-te" = 57005,
    /// ISCII Assamese
    @"x-iscii-as" = 57006,
    /// ISCII Odia
    @"x-iscii-or" = 57007,
    /// ISCII Kannada
    @"x-iscii-ka" = 57008,
    /// ISCII Malayalam
    @"x-iscii-ma" = 57009,
    /// ISCII Gujarati
    @"x-iscii-gu" = 57010,
    /// ISCII Punjabi
    @"x-iscii-pa" = 57011,
    /// Unicode (UTF-7)
    @"utf-7" = 65000,
    /// Unicode (UTF-8)
    @"utf-8" = 65001,
};
