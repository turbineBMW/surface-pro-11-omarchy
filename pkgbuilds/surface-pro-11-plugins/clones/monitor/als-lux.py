#!/usr/bin/env python3
# Ambient light for AutoBrightness.qml: claims the light sensor from
# iio-sensor-proxy and prints its level in lux once a second. The proxy is
# stopped across suspend (surface-pro-11-sensors sleep hook), so nothing is
# printed while it is gone and the sensor is claimed again when it returns.
import sys

from gi.repository import Gio, GLib

NAME = "net.hadess.SensorProxy"
PATH = "/net/hadess/SensorProxy"

conn = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
owned = False
proxy = None


def claim():
    global proxy
    try:
        p = Gio.DBusProxy.new_sync(conn, Gio.DBusProxyFlags.NONE, None, NAME, PATH, NAME, None)
        p.call_sync("ClaimLight", None, Gio.DBusCallFlags.NONE, -1, None)
        proxy = p
    except GLib.Error as e:
        print("als-lux: claim failed: " + e.message, file=sys.stderr, flush=True)


def appeared(_conn, _name, _owner):
    global owned
    owned = True
    claim()


def vanished(_conn, _name):
    global owned, proxy
    owned = False
    proxy = None


def tick():
    if owned and proxy is None:
        claim()
    if proxy is not None:
        v = proxy.get_cached_property("LightLevel")
        if v is not None:
            print("%.3f" % v.unpack(), flush=True)
    return True


Gio.bus_watch_name_on_connection(conn, NAME, Gio.BusNameWatcherFlags.NONE, appeared, vanished)
GLib.timeout_add_seconds(1, tick)
GLib.MainLoop().run()
