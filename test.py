#! /usr/bin/python
# -*-coding:utf-8-*-

import dbus, os
from pamac import transaction

def policykit_auth():
		bus_name = dbus.service.BusName('apps.nano77.gdm3setup', bus)
		dbus.service.Object.__init__(self, bus_name, '/apps/nano77/gdm3setup')

def policykit_test(sender,connexion,action):
	bus = dbus.SystemBus()
	proxy_dbus = connexion.get_object('org.freedesktop.DBus','/org/freedesktop/DBus/Bus', False)
	dbus_info = dbus.Interface(proxy_dbus,'org.freedesktop.DBus')
	sender_pid = dbus_info.GetConnectionUnixProcessID(sender)
	proxy_policykit = bus.get_object('org.freedesktop.PolicyKit1','/org/freedesktop/PolicyKit1/Authority',False)
	policykit_authority = dbus.Interface(proxy_policykit,'org.freedesktop.PolicyKit1.Authority')

	Subject = ('unix-process', {'pid': dbus.UInt32(sender_pid, variant_level=1),
					'start-time': dbus.UInt64(0, variant_level=1)})
	(is_authorized,is_challenge,details) = policykit_authority.CheckAuthorization(Subject, action, {'': ''}, dbus.UInt32(1), '')
	return is_authorized
return pk_granted

if policykit_auth() == 1:
	print('ok')
	transaction.do_refresh()
