#!/bin/sh

set -euf
unset -v IFS

echo() {
  printf '%s\n' "$*"
}

echo "[TEST] ... RUNNING ..."

cd -- "$(dirname -- "$0")"

export SEED="${SEED:-"$(date '+%s')"}"

DO_SH="${DO_SH:-}"
DO_SH_OPTS="${DO_SH_OPTS:-}"
DO_SH_NAME="${DO_SH##*/}"

UUID_DNS='6ba7b810-9dad-11d1-80b4-00c04fd430c8'


########################################################################
############### Preparation

fixpath() {
  eval "
    case \"\${$1}\" in (.|..|/*|./*|../*|'') return 0; esac
    $1=\"./\${$1}\"
  "
}

TMPDIR="${TMPDIR:-/tmp}"
TMPDIR="${TMPDIR%/}/uuid-test-$$"
fixpath TMPDIR

cleanup() {
  rm -f -R "${TMPDIR}"
}
trap cleanup EXIT

mkdir -p "${TMPDIR}/bin"
TESTPATH="${TMPDIR}/bin${PATH:+":${PATH}"}"

# hackish replacement of date
cat >"${TMPDIR}/bin/date" <<'EOT'
#!/bin/sh
set -euf
exec awk -v seed="${SEED}" -v fmt="$1" '
BEGIN {
  srand(seed)
  if (fmt ~ "^[+]") {
    t_s = int(rand() * 4294967296)
    t_N = int(rand() * 1000000000)
    t_Y = int(rand() * 10000); no_leap = (t_Y % 100 ? t_Y % 4 : t_Y % 400)
    t_m = int(rand() * 12 + 1)
    t_d = int(rand() * (t_m ~ /^([13578]|10|12)$/ ? 31 \
                        : (t_m != 2 ? 30 : (no_leap ? 28 : 29))) + 1)
    t_H = int(rand() * 24)
    t_M = int(rand() * 60)
    gsub(/%s/, t_s, fmt)
    gsub(/%N/, sprintf("%09d", t_N), fmt)
    gsub(/%Y/, sprintf("%04d", t_Y), fmt)
    gsub(/%m/, sprintf("%02d", t_m), fmt)
    gsub(/%d/, sprintf("%02d", t_d), fmt)
    gsub(/%H/, sprintf("%02d", t_H), fmt)
    gsub(/%M/, sprintf("%02d", t_M), fmt)
    print substr(fmt, 2)
  } else {
    exit 1
  }
  exit 0
}
'
EOT
chmod +x "${TMPDIR}/bin/date"

uuid() {
  $DO_SH $DO_SH_OPTS ./uuid ${1+"$@"}
}
uuid_s() {
  $DO_SH $DO_SH_OPTS ./uuid -s"${SEED}" ${1+"$@"}
}
uuid_ss() (
  set -e
  export PATH="${TESTPATH}"
  $DO_SH $DO_SH_OPTS ./uuid -s"${SEED}" ${1+"$@"}
)

checkname=unnamed
checkpoint=0
scorepoint=0
checkpoint() {
  : $(( scorepoint += 1 ))
  if [ 0 -lt "$#" ]; then
    if [ x"${checkname}" = x"$*" ]; then
      : $(( checkpoint += 1 ))
    else
      checkname="$*"
      checkpoint=1
    fi
  else
    checkname=unnamed
    checkpoint="${scorepoint}"
  fi
}

on_exit() {
  exitcode="$?"
  cleanup
  if [ 0 -eq "${exitcode}" ]; then
    #cleanup
    echo "[TEST] ALL ${scorepoint} TESTS PASSED"
  else
    echo "[TEST] TEST#${scorepoint} FAILED: ${checkname} #${checkpoint}"
    #echo "[TEST] tests files remaining at \"${TMPDIR}\""
    exit 1
  fi
}
trap on_exit EXIT

echo "[TEST] SEED=${SEED}"
echo "[TEST] DO_SH=${DO_SH}"
echo "[TEST] DO_SH_OPTS=${DO_SH_OPTS}"
echo "[TEST] TMPDIR=\"${TMPDIR}\""
echo "[TEST] ... TESTING ..."


########################################################################
############### utils

check_ver_var() {
  [ 36 -eq "${#3}" ]
  IFS='-'; set -- "$1" "$2" $3; unset -v IFS
  [ 7 -eq "$#" ]
  [ '8-4-4-4-12' = "${#3}-${#4}-${#5}-${#6}-${#7}" ]
  case "$3$4$5$6$7" in (*[!0-9A-F-a-f]*) false; esac
  # match version
  [ x"$1" = x"${5%???}" ]
  # match variant
  case "$2" in
    (1) [ 2 -eq "$(( 0x$6 >> 14 ))" ] ;;
    (2) [ 6 -eq "$(( 0x$6 >> 13 ))" ] ;;
    (*) false
  esac
}

uuid_v_test() (
  set -e
  i=0 ver="${1%-*}" var="${1#*-}"; shift
  while [ 10 -ge "$(( i += 1 ))" ]; do
    result="$(uuid v"${ver}" ${1+"$@"})"
    check_ver_var "${ver}" "${var}" "${result}"
  done
)


########################################################################
############### v4

checkpoint v4; result="$(uuid_s v4)"
checkpoint v4; check_ver_var 4 1 "${result}"
checkpoint v4; [ "${result}" = "$(uuid_s)" ]
checkpoint v4; [ "${result}" = "$(uuid_s v4)" ]
checkpoint v4; uuid_v_test 4-1


########################################################################
############### v3

checkpoint v3; result="$(uuid v3 "${UUID_DNS}" www.example.com)"
checkpoint v3; check_ver_var 3 1 "${result}"
checkpoint v3; [ "${result}" = "$(uuid v3 "${UUID_DNS}" www.example.com)" ]
checkpoint v3; [ "${result}" = '5df41881-3aed-3515-88a7-2f4a814cf09e' ]
checkpoint v3; uuid_v_test 3-1 "${UUID_DNS}" www.example.com


########################################################################
############### v5

checkpoint v5; result="$(uuid v5 "${UUID_DNS}" www.example.com)"
checkpoint v5; check_ver_var 5 1 "${result}"
checkpoint v5; [ "${result}" = "$(uuid v5 "${UUID_DNS}" www.example.com)" ]
checkpoint v5; [ "${result}" = '2ed6657d-e927-568b-95e1-2665a8aea6a2' ]
checkpoint v5; uuid_v_test 5-1 "${UUID_DNS}" www.example.com


########################################################################
############### v1, v2, v6, v7, v8

if [ mksh != "${DO_SH_NAME}" ]; then  # TODO: 64-bit math
checkpoint v1; result="$(uuid_ss v1)"
checkpoint v1; check_ver_var 1 1 "${result}"
checkpoint v1; [ "${result}" = "$(uuid_ss v1)" ]
checkpoint v1; uuid_v_test 1-1

checkpoint v2; result="$(uuid_ss v2 7 6)"
checkpoint v2; check_ver_var 2 1 "${result}"
checkpoint v2; [ "${result}" = "$(uuid_ss v2 7 6)" ]
checkpoint v2; uuid_v_test 2-1 7 6

checkpoint v6; result="$(uuid_ss v6)"
checkpoint v6; check_ver_var 6 1 "${result}"
checkpoint v6; [ "${result}" = "$(uuid_ss v6)" ]
checkpoint v6; uuid_v_test 6-1

checkpoint v7; result="$(uuid_ss v7)"
checkpoint v7; check_ver_var 7 1 "${result}"
checkpoint v7; [ "${result}" = "$(uuid_ss v7)" ]
checkpoint v7; uuid_v_test 7-1
fi

checkpoint v8; result="$(uuid_ss v8)"
checkpoint v8; check_ver_var 8 1 "${result}"
checkpoint v8; [ "${result}" = "$(uuid_ss v8)" ]
checkpoint v8; uuid_v_test 8-1


########################################################################
############### -g, --guid

checkpoint --guid v4; result="$(uuid -g v4)"
checkpoint --guid v4; check_ver_var 4 2 "${result}"
checkpoint --guid v4; uuid_v_test 4-2 -g

checkpoint --guid v3; result="$(uuid -g v3 "${UUID_DNS}" www.example.com)"
checkpoint --guid v3; check_ver_var 3 2 "${result}"
checkpoint --guid v3; uuid_v_test 3-2 "${UUID_DNS}" www.example.com -g

checkpoint --guid v5; result="$(uuid -g v5 "${UUID_DNS}" www.example.com)"
checkpoint --guid v5; check_ver_var 5 2 "${result}"
checkpoint --guid v5; uuid_v_test 5-2 "${UUID_DNS}" www.example.com -g

if [ mksh != "${DO_SH_NAME}" ]; then  # TODO: 64-bit math
checkpoint --guid v1; result="$(uuid -g v1)"
checkpoint --guid v1; check_ver_var 1 2 "${result}"
checkpoint --guid v1; uuid_v_test 1-2 -g

checkpoint --guid v2; result="$(uuid -g v2 7 6)"
checkpoint --guid v2; check_ver_var 2 2 "${result}"
checkpoint --guid v2; uuid_v_test 2-2 7 6 -g

checkpoint --guid v6; result="$(uuid -g v6)"
checkpoint --guid v6; check_ver_var 6 2 "${result}"
checkpoint --guid v6; uuid_v_test 6-2 -g

checkpoint --guid v7; result="$(uuid -g v7)"
checkpoint --guid v7; check_ver_var 7 2 "${result}"
checkpoint --guid v7; uuid_v_test 7-2 -g
fi

checkpoint --guid v8; result="$(uuid -g v8)"
checkpoint --guid v8; check_ver_var 8 2 "${result}"
checkpoint --guid v8; uuid_v_test 8-2 -g


########################################################################
############### -b, --binary

uuid_bs_test() {
  uuid_s -b "$@"             >"${TMPDIR}/1"
  uuid_s    "$@" | xxd -r -p >"${TMPDIR}/2"
  cmp "${TMPDIR}/1" "${TMPDIR}/2"
  [ 16 -eq "$(wc -c <"${TMPDIR}/1")" ]
  [ 16 -eq "$(wc -c <"${TMPDIR}/2")" ]
  [ 32 -eq "$(xxd -p <"${TMPDIR}/1" | tr -c -d 0-9A-Fa-f | wc -c)" ]
  [ 32 -eq "$(xxd -p <"${TMPDIR}/2" | tr -c -d 0-9A-Fa-f | wc -c)" ]
}

checkpoint --binary v4
uuid_bs_test v4

checkpoint --binary v3
uuid_bs_test v3 "${UUID_DNS}" www.example.com
[ '5df418813aed351588a72f4a814cf09e' = "$(xxd -p <"${TMPDIR}/1")" ]

checkpoint --binary v5
uuid_bs_test v5 "${UUID_DNS}" www.example.com
[ '2ed6657de927568b95e12665a8aea6a2' = "$(xxd -p <"${TMPDIR}/1")" ]

if [ mksh != "${DO_SH_NAME}" ]; then  # TODO: 64-bit math
checkpoint --binary v1; uuid_bs_test v1 7 6 555555555555
checkpoint --binary v1; uuid_bs_test v1 7 6
checkpoint --binary v1; uuid_bs_test v1 7
checkpoint --binary v1; (set -e; export PATH="${TESTPATH}"; uuid_bs_test v1)

checkpoint --binary v2; uuid_bs_test v2 7 6 5 4 333333333333
checkpoint --binary v2; uuid_bs_test v2 7 6 5 4
checkpoint --binary v2; uuid_bs_test v2 7 6 5
checkpoint --binary v2; (set -e; export PATH="${TESTPATH}"; uuid_bs_test v2 7 6)

checkpoint --binary v6; uuid_bs_test v6 7 6 555555555555
checkpoint --binary v6; uuid_bs_test v6 7 6
checkpoint --binary v6; uuid_bs_test v6 7
checkpoint --binary v6; (set -e; export PATH="${TESTPATH}"; uuid_bs_test v6)

checkpoint --binary v7; uuid_bs_test v7 7 6 5 444444444444
checkpoint --binary v7; uuid_bs_test v7 7 6 5
checkpoint --binary v7; uuid_bs_test v7 7 6
checkpoint --binary v7; uuid_bs_test v7 7
checkpoint --binary v7; (set -e; export PATH="${TESTPATH}"; uuid_bs_test v7)
fi

checkpoint --binary v8; uuid_bs_test v8 7 6 5 4 3 222222222222
checkpoint --binary v8; uuid_bs_test v8 7 6 5 4 3
checkpoint --binary v8; uuid_bs_test v8 7 6 5 4
checkpoint --binary v8; uuid_bs_test v8 7 6 5
checkpoint --binary v8; uuid_bs_test v8 7 6
checkpoint --binary v8; uuid_bs_test v8 7
checkpoint --binary v8; (set -e; export PATH="${TESTPATH}"; uuid_bs_test v8)


########################################################################
############### --binary --guid

uuid_bgs_test() (
  uuid_ss -b  "$@" >"${TMPDIR}/1"
  uuid_ss -bg "$@" >"${TMPDIR}/2"
  s1="$(xxd -p <"${TMPDIR}/1")"
  s2="$(xxd -p <"${TMPDIR}/2")"
  [ x"${s1#?????????????????}" = x"${s2#?????????????????}" ]
  s1_0="${s1%????????????????}" s2_0="${s2%????????????????}"
  s1_1="${s1_0%????????}" s2_1="${s2_0%????????}"
  s1_0="${s1_0#????????}" s2_0="${s2_0#????????}"
  s1_2="${s1_0%????}" s2_2="${s2_0%????}"
  s1_3="${s1_0#????}" s2_3="${s2_0#????}"
  s1_0="${s1#????????????????}" s2_0="${s2#????????????????}"
  s1_4="${s1_0%????????????}" s2_4="${s2_0%????????????}"
  check_ver_var "${1#v}" 1 "00000000-0000-${s1_3}-${s1_4}-000000000000"
  check_ver_var "${1#v}" 2 "00000000-0000-${s2_3#??}00-${s2_4}-000000000000"
  while [ 2 -le "${#s1_1}" ]; do
    [ x"${s1_1%"${s1_1#??}"}" = x"${s2_1#"${s2_1%??}"}" ]
    s1_1="${s1_1#??}"
    s2_1="${s2_1%??}"
  done
  while [ 2 -le "${#s1_2}" ]; do
    [ x"${s1_2%"${s1_2#??}"}" = x"${s2_2#"${s2_2%??}"}" ]
    s1_2="${s1_2#??}"
    s2_2="${s2_2%??}"
  done
  while [ 2 -le "${#s1_3}" ]; do
    [ x"${s1_3%"${s1_3#??}"}" = x"${s2_3#"${s2_3%??}"}" ]
    s1_3="${s1_3#??}"
    s2_3="${s2_3%??}"
  done
)

checkpoint --binary --guid v4
uuid_bgs_test v4

checkpoint --binary --guid v3
uuid_bgs_test v3 "${UUID_DNS}" www.example.com
[ '8118f45ded3a1535c8a72f4a814cf09e' = "$(xxd -p <"${TMPDIR}/2")" ]

checkpoint --binary --guid v5
uuid_bgs_test v5 "${UUID_DNS}" www.example.com
[ '7d65d62e27e98b56d5e12665a8aea6a2' = "$(xxd -p <"${TMPDIR}/2")" ]

if [ mksh != "${DO_SH_NAME}" ]; then  # TODO: 64-bit math
checkpoint --binary --guid v1; uuid_bgs_test v1

checkpoint --binary --guid v2; uuid_bgs_test v2 7 6

checkpoint --binary --guid v6; uuid_bgs_test v6

checkpoint --binary --guid v7; uuid_bgs_test v7
fi

checkpoint --binary --guid v8; uuid_bgs_test v8


########################################################################
############### -d, --decode

unset -v uuid_version uuid_variant \
         uuid_period uuid_sequence uuid_node \
         uuid_domain uuid_identifier \
         uuid_second uuid_subsecond \
         uuid_year uuid_month uuid_day uuid_hour uuid_minute

uuid_d_test() (
  set -e
  i=0
  while [ 10 -ge "$(( i += 1 ))" ]; do
    ! case "$1" in (v[1267]) false; esac || return 1
    result="$(uuid -d "$@")"
    [ x"${result}" = x"$(uuid -d "$1" $result)" ]
  done
)
uuid_ds_test() {
  ! case "$1" in (v[12678]) false; esac || return 1
  result="$(uuid_s -d "$@")"
  [ x"${result}" = x"$(uuid_s -d "$1" $result)" ]
}
uuid_0s_test() {
  ! case "$1" in (v[12678]) false; esac || return 1
  result="$(uuid_s "$@")"
  [ x"${result}" = x"$(uuid_s v0 "${result}")" ]
}
uuid_0ds_test() (
  set -e
  ver="${1%-*}" var="${1#*-}"; shift
  ! case "${ver}" in ([12345678]) false; esac || return 1
  result="$(uuid_ss v"${ver}" ${1+"$@"})"
  eval "$(uuid -d v0 "${result}")"
  [ "${ver}" = "${uuid_version}" ]
  [ "${var}" = "${uuid_variant}" ]
  case "${ver}" in ([345]) return 0; esac
  result="$(uuid_ss -d v"${ver}" ${1+"$@"})"
  set -- $result
  case "${ver}" in
    (1|6)
      [ x"$1" = x"${uuid_period}" ]
      [ x"$2" = x"${uuid_sequence}" ]
      [ x"$3" = x"${uuid_node}" ]
      ;;
    (2)
      [ x"$1" = x"${uuid_domain}" ]
      [ x"$2" = x"${uuid_identifier}" ]
      [ x"$3" = x"${uuid_period}" ]
      [ x"$4" = x"${uuid_sequence}" ]
      [ x"$5" = x"${uuid_node}" ]
      ;;
    (7)
      [ x"$1" = x"${uuid_second}" ]
      [ x"$2" = x"${uuid_subsecond}" ]
      [ x"$3" = x"${uuid_sequence}" ]
      [ x"$4" = x"${uuid_node}" ]
      ;;
    (8)
      [ x"$1" = x"${uuid_year}" ]
      [ x"$2" = x"${uuid_month}" ]
      [ x"$3" = x"${uuid_day}" ]
      [ x"$4" = x"${uuid_hour}" ]
      [ x"$5" = x"${uuid_minute}" ]
      [ x"$6" = x"${uuid_node}" ]
  esac
)

checkpoint --decode v4; uuid_0ds_test 4-1
checkpoint --decode v4; uuid_0ds_test 4-2 -g

checkpoint --decode v3; uuid_0ds_test 3-1 "${UUID_DNS}" www.example.com
checkpoint --decode v3; uuid_0ds_test 3-2 "${UUID_DNS}" www.example.com -g

checkpoint --decode v5; uuid_0ds_test 5-1 "${UUID_DNS}" www.example.com
checkpoint --decode v5; uuid_0ds_test 5-2 "${UUID_DNS}" www.example.com -g

if [ mksh != "${DO_SH_NAME}" ]; then  # TODO: 64-bit math
checkpoint --decode v1; uuid_ds_test v1
checkpoint --decode v1; uuid_d_test v1
checkpoint --decode v1; uuid_0s_test v1
checkpoint --decode v1; uuid_0ds_test 1-1
checkpoint --decode v1; uuid_0ds_test 1-2 -g

checkpoint --decode v2; uuid_ds_test v2 7 6
checkpoint --decode v2; uuid_d_test v2 7 6
checkpoint --decode v2; uuid_0s_test v2 7 6
checkpoint --decode v2; uuid_0ds_test 2-1 7 6
checkpoint --decode v2; uuid_0ds_test 2-2 7 6 -g

checkpoint --decode v6; uuid_ds_test v6
checkpoint --decode v6; uuid_d_test v6
checkpoint --decode v6; uuid_0s_test v6
checkpoint --decode v6; uuid_0ds_test 6-1
checkpoint --decode v6; uuid_0ds_test 6-2 -g

checkpoint --decode v7; uuid_ds_test v7
checkpoint --decode v7; uuid_d_test v7
checkpoint --decode v7; uuid_0s_test v7
checkpoint --decode v7; uuid_0ds_test 7-1
checkpoint --decode v7; uuid_0ds_test 7-2 -g
fi

checkpoint --decode v8; uuid_ds_test v8
checkpoint --decode v8; uuid_0s_test v8
checkpoint --decode v8; uuid_0ds_test 8-1
checkpoint --decode v8; uuid_0ds_test 8-2 -g


########################################################################
############### TODO smoke tests


########################################################################
############### TODO third-party
