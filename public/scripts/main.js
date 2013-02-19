$(document).ready(function () {
	uglyDate = $(".current-date").text()
	if (uglyDate != ""){
		$(".current-date").empty()
		$(".current-date").append("Submitted: " + moment(uglyDate).format('dddd MMMM Do YYYY'))
	}
	else {
		$(".current-date").append(moment().format('dddd MMMM Do YYYY'))
	}
	
});

// On Button click

// Increment value by 1

// Find which shortlist item it is

// POST to server to increment that items fav score by 1