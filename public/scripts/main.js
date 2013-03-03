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

function favThis(favObj) {

	shortAuthor = $(favObj).parent().parent().children('.short-author').children('a:eq(1)').text();
	console.log(shortAuthor);

	shortID = $(favObj).parent().parent().children('.short-author').attr('title');
	console.log(shortID);
	if (makeRequest(shortAuthor, shortID) == true) {
		console.log("Trying to increment count")
		changeFav(favObj, "increment");
		
	} else {
		console.log("Trying to decrement count")
		changeFav(favObj, "decrement");
		
	}

};

function makeRequest(shortAuthor, shortID) {
	var requestURL = "/" + shortAuthor + "/fav/" + shortID;
	console.log("Query being made for: "+ requestURL)
	var canFav = false;

	$.ajax({
		type: "POST",
		url: requestURL,
		async: false,
		success: function(data) {
			if (data.canFav == true){
				canFav = true;
				console.log("Can fav this")
			} else if (data.canFav == false) {
				canFav = false;
				console.log("Cannot fav this so will decrement fave value")
			}
		}
	});

	return canFav
}

function changeFav(favObj, changeValue) {
	current_fav_count = parseInt($(favObj).parent().children('.short-fav-count').text());
	$(favObj).parent().children('.short-fav-count').empty();
	if (changeValue == "increment") {
		current_fav_count ++;
		$(favObj).css({"color":"#EB5858"});
		$(favObj).parent().children('.short-fav-count').text(current_fav_count);
		console.log("incremnt successful")
	}
	else {
		current_fav_count --;
		$(favObj).css({"color":"#656262"});
		$(favObj).parent().children('.short-fav-count').text(current_fav_count);
		console.log("decrement successful")
	}

}

// On Button click

// Increment value by 1

// Find which shortlist item it is

// POST to server to increment that items fav score by 1