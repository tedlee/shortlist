require "sinatra" 
#require "erb"
require "pry"
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
	property :url,			String, :length => 200
	property :title,		String, :length => 120
	property :description,	String, :length => 120

	belongs_to :user
end


configure :development do
	DataMapper.setup(:default, ENV['DATABASE_URL'] || "postgres://localhost/shortlist")
	DataMapper.auto_upgrade!
	DataMapper.finalize
	#DataMapper.auto_migrate! # wipes everything
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
	@title = "Steno - Changelog"
	erb :changelog
end

post "/signup" do
	User.create(:username => params[:username], :firstname => params[:firstname], :lastname => params[:lastname], :user_avatar => params[:user_avatar], :created_at => Time.now)
	redirect back
end

post "/:username/add" do
	@user = User.get params[:username]

	puts "username submitted is: #{@user.username}"

	if @user

		Link.create(:url => params[:url], :title => params[:title], :description => params[:description],  :user_username => @user.username)
		redirect back
	end
end

get "/:username" do
	@user = User.get params[:username]

	if @user.links
		@links = Link.all(:user_username => @user.username)
	end

	# To get all the links from a user do @user.links.all()

	if @user
		@title = "The Shortlist of #{@user}"
		erb :user
	else
		"That user doesn't exist yet :("
	end
end






not_found do  
	halt 404, 'No page for you.'  
end