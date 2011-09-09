/*
 * Premailer bookmarklet for local scripts
 *
 * Copyright (c) 2009 Dialect Communications Group (dialect.ca)
 */
 
/*jslint bitwise: true, browser: true, eqeqeq: true, immed: true, newcap: true, nomen: true, onevar: false, plusplus: true, regexp: true, undef: true, white: true, indent: 4 */
"use strict";

function premailer_is_local() {
	if (document.location.protocol === 'file:' || 
	    document.location.host === 'localhost' || 
	    document.location.host === '127.0.0.1') {
		return true;
	} else {
		return false;
	}
}

if (premailer_is_local()) {
	var req = new XMLHttpRequest();
	var data = '';
	req.open('GET', document.location, false);
	req.send(null);
	if (req.status !== 200 && req.status !== 0) {
		alert('An errror occurred loading the current document.');
	} else {
		data = req.responseText;

		var f = document.createElement('form');
		f.style.display  = 'none';
		f.method = 'POST';
		f.action = 'http://premailer.dialect.ca/?bookmarklet=true&utm_source=local_bookmarklet&utm_medium=bookmarklet&utm_campaign=Tools';
		
		var f_html = document.createElement('textarea');
		f_html.name = 'html';
		f_html.innerHTML = data;

		var f_mode = document.createElement('input');
		f_mode.name = 'content_source';
		f_mode.type = 'hidden';
		f_mode.value = 'html';

		f.appendChild(f_html);
		f.appendChild(f_mode);

		var b = document.getElementsByTagName('body')[0];
		b.appendChild(f);

		f.submit();
	}
} else {
	var dest = 'http://premailer.dialect.ca/?bookmarklet=true&url=';
	var tracking = '&utm_source=remote_bookmarklet&utm_medium=bookmarklet&utm_campaign=Tools';
	window.location = dest + encodeURIComponent(document.URL) + tracking;
}
