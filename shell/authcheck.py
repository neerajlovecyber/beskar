#!/usr/bin/env python3
"""Does this password open the lock screen?  Run it in a terminal:   python3 shell/authcheck.py

It asks PAM exactly as the lock screen does (the "login" service, for your own user) and says yes or no, without
touching your session. Three wrong answers in a row make the system refuse you for about 10 minutes (pam_faillock),
the login screen included; `faillock --user $USER --reset` clears that."""
import ctypes, getpass, os, pwd, sys
from ctypes import CDLL, POINTER, Structure, byref, c_char_p, c_int, c_void_p, CFUNCTYPE, cast, sizeof

pam = CDLL("libpam.so.0")
libc = CDLL("libc.so.6")
libc.calloc.restype = c_void_p
libc.strdup.restype = c_void_p


class Msg(Structure):
    _fields_ = [("style", c_int), ("text", c_char_p)]


class Resp(Structure):
    _fields_ = [("text", c_char_p), ("code", c_int)]


CONV = CFUNCTYPE(c_int, c_int, POINTER(POINTER(Msg)), POINTER(POINTER(Resp)), c_void_p)


class Conv(Structure):
    _fields_ = [("conv", CONV), ("data", c_void_p)]


user = pwd.getpwuid(os.getuid()).pw_name
secret = getpass.getpass(f"Password for {user}: ").encode()


def answer(n, msgs, resp, data):
    r = libc.calloc(n, sizeof(Resp))
    arr = cast(r, POINTER(Resp))
    for i in range(n):
        arr[i].text = cast(libc.strdup(secret), c_char_p)
    resp[0] = arr
    return 0


conv = Conv(CONV(answer), None)
handle = c_void_p()
service = b"pleamar" if os.path.exists("/etc/pam.d/pleamar") else b"login"
if pam.pam_start(service, user.encode(), byref(conv), byref(handle)) != 0:
    sys.exit("PAM would not start")
code = pam.pam_authenticate(handle, 0)
if code == 0:
    code = pam.pam_acct_mgmt(handle, 0)
pam.pam_end(handle, code)
print("OK: this password opens the lock screen." if code == 0 else f"NO: PAM refused it (code {code}; 7 = wrong password, 6 or 8 = the account is locked or expired).")
sys.exit(0 if code == 0 else 1)
