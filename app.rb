require "sinatra"
require "data_mapper"

configure :production do
	require 'newrelic_rpm'
end

set :views, settings.root + '/views'

class User  
	include DataMapper::Resource

	# For some reason adding the property id leads to the following error: 
	# The number of arguments for the key is invalid, expected 2 but was 1

	# This might because of the number of arguments that are passed in at POST /:signup

	#property :id, 			Serial
	property :username,		String, required: true, :key => true
	property :firstname, 	String, required: true
	property :lastname, 	String, required: true
	#property :email, 		String, format: :email_address  
	property :user_avatar, 	Text, :format => :url, required: false
	property :created_at, 	DateTime

	def username= new_username
		super new_username.downcase
	end

	has n, :links
end

class Link
	include DataMapper::Resource

	property :id,			Serial
	property :url,			String, :length => 500, required: true
	property :title,		String, :length => 120, required: true
	property :favourites,	Integer, required: false, default: 1
	#property :description,	String, :length => 120
	property :created_at, 	DateTime

	belongs_to :user
end


configure :development do
	DataMapper.setup(:default, ENV['DATABASE_URL'] || "postgres://localhost/shortlist")
	DataMapper.auto_upgrade!
	#DataMapper.auto_migrate! # wipes everything
	DataMapper.finalize
	
end 

configure :production do
	DataMapper.setup(:default, ENV['DATABASE_URL'] || "postgres://localhost/shortlist")
	DataMapper.auto_upgrade!
	DataMapper.finalize

	#shouldn't run auto upgrade in production
	
end

get "/" do
	@title = "Shortlist"
	#@user_count = User.all().count.to_s()
	#set :erb, :layout => false
	@links = Link.all()
	erb :index
end

get "/signup" do
	@users = User.all(:order => :username.desc)
	#set :erb, :layout => false
	erb :signup
end

get "/changelog" do
	@title = "Shortlist - Signup"
	erb :changelog
end

post "/signup" do
	
	User.create(:username => params[:username], :firstname => params[:firstname], :lastname => params[:lastname], :user_avatar => params[:user_avatar], :created_at => Time.now)
	redirect params[:username]
end

post "/:username/add" do
	@user = User.get params[:username]

	puts "username submitted is: #{@user.username}"

	if @user
		Link.create(:url => params[:url], :title => params[:title], :user_username => @user.username, :created_at => Time.now)
		redirect back
	end
end

get "/:username" do
	@user = User.get params[:username]
	#@links = Link.all(:user_username => @user.username)

	# To get all the links from a user do @user.links.all()

	if @user
		@title = "The Shortlist of #{@user.username}"
		erb :user
	else
		"That user doesn't exist yet :("
	end
end

not_found do  
	halt 404, 'No page for you.'  
end


def youtube_embed(youtube_url)

	# Regex from https://gist.github.com/1254889
	youtube_url[/(youtu\.be\/|youtube\.com\/(watch\?(.*&)?v=|(embed|v)\/))([^\?&"'>]+)/]
	youtube_id = $5

	%Q{<iframe title="YouTube video player" width="100%" height="550" src="http://www.youtube.com/embed/#{ youtube_id }" frameborder="0" allowfullscreen></iframe>}
end