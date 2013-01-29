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
	#property :id, 			Serial, key: true
	property :username,		String, required: true, key: true
	property :firstname, 	String, required: true
	property :lastname, 	String, required: true
	#property :email, 		String, format: :email_address  
	property :user_avatar, 	Text, :format => :url, required: false
	property :created_at, 	DateTime

	def username= new_username
		super new_username.downcase
	end


end

configure :development do
	DataMapper.setup(:default, ENV['DATABASE_URL'] || "postgres://localhost/shortlist")
	#DataMapper.finalize
	DataMapper.auto_migrate! # wipes everything
end 

configure :production do
	DataMapper.setup(:default, ENV['DATABASE_URL'] || "postgres://localhost/shortlist")
	DataMapper.finalize

	#shouldn't run auto upgrade in production
	DataMapper.auto_upgrade!
end

get "/" do
	@title = "Shortlist"
	#@user_count = User.all().count.to_s()
	#set :erb, :layout => false
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

get "/:username" do
	@user = User.get params[:username]
	if @user
		@username = "#{params[:username]}"
		erb :user
	else
		"That user doesn't exist yet :("
	end
end






not_found do  
	halt 404, 'No page for you.'  
end