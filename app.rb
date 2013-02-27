require "sinatra"
require "data_mapper"
require "warden"
require 'dm-types'
require "sinatra/contrib"
require "jsonify"

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
	property :username,		String, required: true, unique: true, :key => true
	property :password,		BCryptHash
	property :firstname, 	String, required: true
	property :lastname, 	String, required: true
	#property :email, 		String, format: :email_address  
	property :user_avatar, 	Text, :format => :url, required: true
	property :created_at, 	DateTime

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
	User.get(username)
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

	#@user_count = User.all().count.to_s()
	#set :erb, :layout => false
	@links = Link.all()
	erb :index
end

get "/signup" do
	@title = "Shortlist - Sign Up"
	erb :signup
end

post "/signup" do
	User.create(:username => params[:username], :password => params[:password], :firstname => params[:firstname], :lastname => params[:lastname], :user_avatar => params[:user_avatar], :created_at => Time.now)

	puts params[:user_avatar]

	if env['warden'].authenticate
		redirect "/#{env['warden'].user.username}"
	else
		redirect '/login'
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
	@title = "Shortlist - Signup"
	erb :changelog
end

get "/about" do
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
	@user = User.get params[:username]

	puts "username submitted is: #{@user.username}"

	# Checks to make sure that person is signed in before submitting link
	if (@user && env['warden'].authenticate) && @user.username == env['warden'].user.username
		Link.create(:url => params[:url], :title => params[:title], :user_username => @user.username, :created_at => Time.now)
		redirect back
	else
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
	@user = User.get params[:username]
	@link = @user.links.get params[:id]

	#@links = Link.all(:user_username => @user.username)

	# To get all the links from a user do @user.links.all()

	if @user && @link
		@title = "The Shortlist of #{@user.username}"
		erb :short
	else
		"That Short doesn't exist :("
	end
end

post "/:username/edit/:id" do
	@user = User.get params[:username]
	@link = @user.links.get params[:id]

	if ((env['warden'].authenticate) && (@user.username == env['warden'].user.username)) || ((env['warden'].authenticate) && (ENV['ADMIN_USERNAME'] == env['warden'].user.username))
		if @link.update(:url => params[:url], :title => params[:title])
			redirect back
		else
			redirect back
		end
	end
end

post "/:username/delete/:id" do
	@user = User.get params[:username]
	@link = @user.links.get params[:id]

	if ((env['warden'].authenticate) && (@user.username == env['warden'].user.username)) || ((env['warden'].authenticate) && (ENV['ADMIN_USERNAME'] == env['warden'].user.username))
		if @link.destroy
			redirect "/#{ @user.username }"
		else
			redirect "/#{ @user.username }"
		end
	end
end



not_found do  
	halt 404, 'No page for you.'  
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