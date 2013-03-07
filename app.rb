require "sinatra"
require "data_mapper"
require "warden"
require 'dm-types'
require "sinatra/contrib"
require "jsonify"
require "faraday"

configure :production do
	require 'newrelic_rpm'
end

set :views, settings.root + '/views'

class User  
	include DataMapper::Resource

	# For some reason adding the property id leads to the following error: 
	# The number of arguments for the key is invalid, expected 2 but was 1

	# This might because of the number of arguments that are passed in at POST /:signup

	# Note: when adding new fields you can't require them immediately because the migration thinks that that field
	# should have a value (and for all instances of the User class they do not)

	property :id, 				Serial, require: false
	property :username,			String, required: true, unique: true
	property :password,			BCryptHash
	property :fullname,			String
	property :user_email,		String, format: :email_address
	property :user_avatar,		Text, :format => :url, default: "http://s3.amazonaws.com/shortlistapp/1362446767739default-avatar.png"
	property :faves_received,	Integer, default: 0
	property :updated_at,		DateTime, required: false
	property :created_at, 		DateTime

	def username= new_username
		super new_username.downcase
	end

	def self.authenticate(username, password)
		user = first(:username => username)
		if user 
			if user.password != password
				user = nil
			end
		end
		user
	end

	has n, :links
end

class Link
	include DataMapper::Resource

	property :id,				Serial
	property :url,				String, :length => 500, required: true
	property :title,			String, :length => 120, required: true
	property :num_favourites,	Integer, required: false, default: 1
	#property :description,		String, :length => 120
	property :created_at, 		DateTime

	belongs_to :user
	has n, :favourites
end

class Favourite
	include DataMapper::Resource
	property :id,			Serial
	property :giver,		String
	property :created_at, 	DateTime
	belongs_to :link
end



configure :development do
	DataMapper.setup(:default, ENV['DATABASE_URL'] || "postgres://localhost/shortlist3")
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

use Rack::Session::Cookie, :secret => ENV['WARDEN_SESSION_SECRET']

use Warden::Manager do |manager|
	manager.default_strategies :password
	manager.failure_app = FailureApp.new
end

Warden::Manager.serialize_into_session do |user|
	puts '[INFO] serialize into session'
	user.username
end

Warden::Manager.serialize_from_session do |username|
	puts '[INFO] serialize from session'
	#User.get(username)
	User.first(:username => username)
end

Warden::Strategies.add(:password) do
	def valid?
		puts '[INFO] password strategy valid?'
		params['username'] || params['password']
	end

	def authenticate!
		puts '[INFO] password strategy authenticate'
		u = User.authenticate(params['username'], params['password'])
		u.nil? ? fail!('Could not login in') : success!(u)
	end
end

class FailureApp
	def call(env)
		uri = env['REQUEST_URI']
		puts "failure #{env['REQUEST_METHOD']} #{uri}"
	end
end

get "/" do
	@title = "Shortlist"
	@display_nav_avatar = true
	#@user_count = User.all().count.to_s()
	#set :erb, :layout => false
	@links = Link.all()
	erb :index
end

get "/signup" do
	@title = "Shortlist - Sign Up"
	@display_nav_avatar = true
	erb :signup
end

post "/signup" do

	# TODO - add username checking aginst existing usernames and forbidden phrases

	if params[:user_avatar] != ""
		User.create(:username => params[:username], :password => params[:password], :fullname => params[:fullname], :user_email => params[:user_email], :user_avatar => params[:user_avatar], :created_at => Time.now)
	else
		User.create(:username => params[:username], :password => params[:password], :fullname => params[:fullname], :user_email => params[:user_email], :created_at => Time.now)
	end

	if env['warden'].authenticate
		send_welcome_message(params[:user_email], params[:fullname])
		set :erb, :layout => true
		redirect "/#{env['warden'].user.username}"
	else
		puts "not authenticated"
		redirect '/signup'
	end
end

get "/login/?" do
	@title = "Shortlist - Login"
	erb :login
end

post "/login/?" do
	if env['warden'].authenticate
		redirect "/#{env['warden'].user.username}"
	else
		redirect '/login'
	end
end

get "/logout/?" do
	env['warden'].logout
	redirect '/'
end

get "/changelog" do
	@display_nav_avatar = true
	@title = "Shortlist - Signup"
	erb :changelog
end

get "/about" do
	@display_nav_avatar = true
	@title = "Shortlist - About"
	erb :about
end

get '/signS3put' do

	require "cgi"
	require "base64"
	require 'json'

	S3_BUCKET_NAME = ENV['S3_BUCKET_NAME']
	S3_SECRET_KEY = ENV['S3_SECRET_KEY']
	S3_ACCESS_KEY = ENV['S3_ACCESS_KEY']
	S3_URL = 'http://s3.amazonaws.com/'

	objectName = params[:s3_object_name]
	mimeType = params['s3_object_type']
	expires = Time.now.to_i + 100 # PUT request to S3 must start within 100 seconds

	amzHeaders = "x-amz-acl:public-read" # set the public read permission on the uploaded file
	stringToSign = "PUT\n\n#{mimeType}\n#{expires}\n#{amzHeaders}\n/#{S3_BUCKET_NAME}/#{objectName}";
	sig = CGI::escape(Base64.strict_encode64(OpenSSL::HMAC.digest('sha1', S3_SECRET_KEY, stringToSign)))

	{
		signed_request: CGI::escape("#{S3_URL}#{S3_BUCKET_NAME}/#{objectName}?AWSAccessKeyId=#{S3_ACCESS_KEY}&Expires=#{expires}&Signature=#{sig}"),
		url: "http://s3.amazonaws.com/#{S3_BUCKET_NAME}/#{objectName}"
	}.to_json
end

post "/:username/add" do
	#@user = User.get params[:username]
	@user = User.get(env['warden'].user.id)

	puts "username submitted is: #{@user.username} and id is: #{@user.id}"

	# Checks to make sure that person is signed in before submitting link
	if (@user && env['warden'].authenticate) && @user.id == env['warden'].user.id
		Link.create(:url => params[:url], :title => params[:title], :user_id => @user.id, :created_at => Time.now)
		redirect back
	else
		redirect back
	end
end

get "/settings" do

	if (env['warden'].authenticate) #|| ((env['warden'].authenticate) && (ENV['ADMIN_USERNAME'] == env['warden'].user.username))
		#@user = User.get(env['warden'].user.username)
		@user = User.get(env['warden'].user.id)
		@display_nav_avatar = false
		@title = "Settings"
		erb :settings
	else
		"Either that user doesn't exist or you don't have any settings yet. Try logging in."
	end
end

post "/settings" do
	@user = User.get(env['warden'].user.id)
	previous_username = @user.username

	if ((env['warden'].authenticate) && (@user.id == env['warden'].user.id)) || ((env['warden'].authenticate) && (ENV['ADMIN_USERNAME'] == env['warden'].user.username))
		if @user.update(:username => params[:username], :fullname => params[:fullname], :user_email => params[:user_email], :user_avatar => params[:user_avatar])
			if previous_username == params[:username]
				redirect "/#{env['warden'].user.username}"
			else
				env['warden'].logout
				redirect '/'
			end
		else
			redirect back
		end
	end
end

get "/:username" do
	#@user = User.get params[:username]
	@user = User.first(:username => params[:username])

	# @links = Link.all(:user_username => @user.username)
	# To get all the links from a user do @user.links.all()
	# @user.respond_to?(:value)

	if @user
		if (env['warden'].authenticate) && (@user.id != env['warden'].user.id)
			@display_nav_avatar = true
		else
			@display_nav_avatar = false
		end

		@title = "The Shortlist of #{@user.fullname}"
		erb :user
	else
		"That user doesn't exist yet :("
	end
end

get "/api/avatars" do
	@user = User.all

	if @user
	    # JSON reponse containing all user moments

	    content_type :json
	    response = Jsonify::Builder.new(:format => :pretty)
	    response.avatars(@user) do |user|
	    	response.username user.username
	        response.avatar_url user.user_avatar
	    end

	    response.compile!
	else
	    json "avatars" => false
	end

end

get "/:username/:id" do
	#@user = User.get params[:username]
	@user = User.first(:username => params[:username])
	@link = @user.links.get params[:id]

	#@links = Link.all(:user_username => @user.username)

	# To get all the links from a user do @user.links.all()

	if @user && @link
		if (env['warden'].authenticate) && (@user.id != env['warden'].user.id)
			@display_nav_avatar = true
		else
			@display_nav_avatar = false
		end

		@title = "The Shortlist of #{@user.fullname}"
		erb :short
	else
		"That Short doesn't exist :("
	end
end

post "/:username/edit/:id" do
	#@user = User.get params[:username]
	@user = User.get(env['warden'].user.id)
	@link = @user.links.get params[:id]

	if ((env['warden'].authenticate) && (@user.id == env['warden'].user.id)) #|| ((env['warden'].authenticate) && (ENV['ADMIN_USERNAME'] == env['warden'].user.username))
		if @link.update(:url => params[:url], :title => params[:title])
			redirect back
		else
			redirect back
		end
	end
end

post "/:username/delete/:id" do
	@user = User.get(env['warden'].user.id)
	@link = @user.links.get params[:id]

	if ((env['warden'].authenticate) && (@user.id == env['warden'].user.id)) #|| ((env['warden'].authenticate) && (ENV['ADMIN_USERNAME'] == env['warden'].user.username))
		if @link.favourites.destroy && @link.destroy
			redirect "/#{ @user.username }"
		else
			redirect "/#{ @user.username }"
		end
	end
end

post "/fav/:id" do
	#@user = User.first(:username => params[:username])
	@link = Link.get params[:id]
	@user = User.get(@link.user_id)

	puts @link.title

	if (@link && env['warden'].authenticate)
		if @link.favourites.first(:giver => env['warden'].user.id) == nil
			puts "User has not faved this yet"
			Favourite.create(:giver => env['warden'].user.id, :link_id => params[:id], :created_at => Time.now)
			if @link.update(:num_favourites => (@link.num_favourites + 1)) && @user.update(:faves_received => (@user.faves_received + 1))
				json "canFav" => true
			end
		else
			if @user.faves_received > 0
				@user.update(:faves_received => (@user.faves_received - 1))
			end
			@link.update(:num_favourites => (@link.num_favourites - 1))
			@link.favourites.first(:giver => env['warden'].user.id).destroy
			puts "User has faved this already"
			json "canFav" => false
		end
	end

end



not_found do  
	halt 404, 'No page for you. This is just like that episode with the Soup Nazi except on the web.'  
end


def youtube_embed(youtube_url)

	# Regex from https://gist.github.com/1254889
	youtube_url[/(youtu\.be\/|youtube\.com\/(watch\?(.*&)?v=|(embed|v)\/))([^\?&"'>]+)/]
	youtube_id = $5

	# http://www.youtube.com/embed/v1uyQZNg2vE?autoplay=0&controls=0&showinfo=0&autohide=1&loop=0&rel=0&wmode=transparent&enablejsapi=1&modestbranding=1&html5=1
	%Q{<iframe title="YouTube video player" width="100%" height="550" src="http://www.youtube.com/embed/#{ youtube_id }?autoplay=0&iv_load_policy=3&rel=0&theme=light&color=white&controls=2&showinfo=0&autohide=1&loop=0&wmode=transparent&modestbranding=1&html5=1" ></iframe>}
end

def vimeo_embed(vimeo_url)

	vimeo_url.gsub(/https?:\/\/(www.)?vimeo\.com\/([A-Za-z0-9._%-]*)((\?|#)\S+)?/) do
		vimeo_id = $2
		%Q{<iframe src="//player.vimeo.com/video/#{vimeo_id}?portrait=0&color=EB5858" width="100%" height="550" frameborder="0" webkitAllowFullScreen mozallowfullscreen allowFullScreen></iframe>}
	end
end

def soundcloud_embed(soundcloud_url)

	require 'uri'
	require 'net/http'
	require 'json'

	soundcloud_url.gsub(/(https?:\/\/)?(www.)?soundcloud\.com\/.*/) do |match|
		new_uri = match.to_s
		new_uri = (new_uri =~ /^https?\:\/\/.*/) ? URI(new_uri) : URI("http://#{new_uri}")
		new_uri.normalize!

		uri = URI("http://soundcloud.com/oembed")
		params = {:format => 'json', :url => new_uri}.merge(:maxwidth => '', :maxheight => '500', :auto_play => false, :show_comments => false)
		
		uri.query = params.collect { |k,v| "#{k}=#{URI.escape(v.to_s)}" }.join('&')
		
		begin
			response = Net::HTTP.get(uri)
		rescue Errno::ETIMEDOUT
			puts "Can't make request to Soundcloud oembed API"
		end

		if (response != nil) && (response != "")
			JSON.parse(response)["html"]
		else
			"Soundcloud API is down"
		end
	end
end

def send_welcome_message(email, fullname)
	# Send Greeting message
	conn = Faraday.new(:url => 'https://api.mailgun.net/v2') do |faraday|
		faraday.request  :url_encoded
		faraday.adapter  Faraday.default_adapter
	end

	conn.basic_auth('api', 'key-8q69y-ssazgujpbohiedzm4s3oyoz911')
	set :erb, :layout => false

	fields = {
		:from => 'Ted Lee <ted@shortlist.mailgun.org>',
		:to => email,
		:subject => 'Welcome to Shortlist!',
		:html => erb(:welcome_email, :locals => {:fullname => fullname})
	}
	puts fields
	conn.post('shortlist.mailgun.org/messages', fields)
end