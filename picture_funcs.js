function parent_to_url(url) {
    if (url == "frameEERSTE.html") {
	parent.location.href = "overzicht.html";
    } else if (url == "frameLAATSTE.html") {
	parent.location.href = "overzicht.html";
    } else {
	parent.location.href = url;
    }
}
// The capture_size function will execute onload of the page
// and will capture the original size of the picture. 
// This will then be used to ensure that the picture will never needs
// to get bigger than the original size.
var orig_width, orig_height;
function capture_size(picture) {
    orig_width = picture.width;
    orig_height = picture.height;
    resize(picture);
}
function resize(picture) {
    // Verify if resizing is required
    if (navigator.appName == "Netscape") {
	var margin = 16;	// Margin required around the picture. 
	var window_width = window.innerWidth - margin;
	var window_height = window.innerHeight - margin;
    } else if (navigator.appName == "Microsoft Internet Explorer") {
        var margin = 38;	// Margin required around the picture. 
	var window_width = document.body.offsetWidth - margin;
	var window_height = document.body.offsetHeight - margin;
    }
    if ((window_width >= orig_width) && (window_height >= orig_height)) {
	// No resizing required, set picture to original size
	picture.height = orig_height;
	picture.width  = orig_width;
    } else {
	// Resizing required
	width_scale = window_width / orig_width;
	height_scale = window_height / orig_height;
	if (width_scale < height_scale) {
	    picture.width = window_width;
	    picture.height = orig_height * (window_width / orig_width);
	} else {
	    picture.width = orig_width * (window_height / orig_height);
	    picture.height = window_height;
	}
    }
}

