/*
 * Minimal XApp StatusIcon binding using Pamac's Gtk3 Vala namespace.
 * Pamac ships a renamed GTK3 vapi to coexist with GTK4 in one project.
 */
[CCode (cheader_filename = "libxapp/xapp-status-icon.h")]
namespace XApp {
	[CCode (cname = "XAppStatusIcon", type_id = "xapp_status_icon_get_type ()")]
	public class StatusIcon : GLib.Object {
		[CCode (cname = "xapp_status_icon_new")]
		public StatusIcon ();

		[CCode (cname = "xapp_status_icon_any_monitors")]
		public static bool any_monitors ();

		[CCode (cname = "xapp_status_icon_set_icon_name")]
		public void set_icon_name (string icon_name);

		[CCode (cname = "xapp_status_icon_set_tooltip_text")]
		public void set_tooltip_text (string tooltip_text);

		[CCode (cname = "xapp_status_icon_set_visible")]
		public void set_visible (bool visible);

		[CCode (cname = "xapp_status_icon_set_secondary_menu")]
		public void set_secondary_menu (Gtk3.Menu menu);

		public signal void activate (uint button, uint time);
	}
}
