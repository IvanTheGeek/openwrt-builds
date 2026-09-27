# Crash alert on interactive logins (/etc/profile sources profile.d, except in failsafe).
# 'ssh host cmd' and 'ssh host sh -s' never see this: scripts must run 'crashguard status'
# and treat exit 1 and 3 as stop. CG_ROOT is for laptop tests only; it is unset on a router.
[ -x "${CG_ROOT}/usr/sbin/crashguard" ] && "${CG_ROOT}/usr/sbin/crashguard" banner
