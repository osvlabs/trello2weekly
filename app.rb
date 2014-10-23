require 'json'
require 'erb'
require 'time'
require 'yaml'
require 'oauth'
require 'faraday'
require 'sinatra'
require 'sinatra/activerecord'
require 'sinatra/flash'
require 'sinatra/redirect_with_flash'
require './mail'
require './environments'

CONF = YAML.load(File.open('config.yml'))

enable :sessions
set :session_secret, "#{::CONF['Secret']}"

I18n.enforce_available_locales = true

helpers do

  def encrypt(password)
    Digest::SHA256.hexdigest(password)
  end

  def parseJson(url)
    response = Faraday.get(url)
    response_hash = JSON.parse(response.body)
    return response_hash
  end

  def simpleTime(time)
    unless time
      return '待完成'
    end
    t = Time.parse(time)
    return t.strftime("%Y-%m-%d")
  end

  def takeFivedayRange
    d = Date.today
    five_days_range = [ (d - 5).to_s, d ]
    return five_days_range
  end

  def solveState(state)

    case state
    when 'complete'
      status_info = '<span style="color: green">已完成</span>'
    when 'incomplete'
      status_info = '<span style="color: red">待解决</span>'
    end

    return status_info
  end

  def getBoard(token)
    url = "https://api.trello.com/1/members/me/boards?key=#{::CONF['Key']}" +
    "&token=#{token}"

    parseJson(url)
  end

  def getList(token, board_id)
    url = "https://api.trello.com/1/boards/#{board_id}/lists?key=" +
    "#{::CONF['Key']}&token=#{token}"

    parseJson(url)
  end

  def getCards(token, list_id)
    url = "https://api.trello.com/1/lists/#{list_id}/cards?key=" +
    "#{::CONF['Key']}&token=#{token}"

    parseJson(url)
  end

  def getChecklist(token, card_id)
    url = "https://api.trello.com/1/cards/#{card_id}/checklists?key="+
    "#{::CONF['Key']}&token=#{token}"

    parseJson(url)
  end

end

class Auth < ActiveRecord::Base
  validates :username, uniqueness: true
  validates :username, :password, presence: true
end


post '/callback' do
  params['origin']
end

# Login Authentication

get('/login') do
  if session['username']
    redirect '/'
  end
  erb :"user/login"
end

post '/login' do
  if params[:auth]
    @user = Auth.find_by(username: params[:auth]['username'])
    if @user
      if ( params[:auth]['username'] == @user.username &&
        encrypt(params[:auth]['password']) == @user.password )
        session['username'] = params[:auth]['username']
        redirect '/', :notice => '您已成功登录!'
      else
        redirect '/login', :error => ['授权验证失败.']
      end
    end
    redirect '/login', :error => ['当前用户不存在.']
  end
end

# User registration

get ('/user/create') do
  if session['username']
    redirect '/'
  end

  erb :"user/create"
end

post '/user/create' do
  params[:auth]['password'] =
    encrypt(params[:auth]['password'])
  @auth = Auth.new(params[:auth])
  if @auth.save
    session['username'] = params[:auth]['username']
    redirect '/', :notice => 'Congrats! 您已成功注册.'
  else
    redirect '/user/create', :error => @auth.errors.full_messages
  end
end

# Dashboard

get ('/') do
  if session['username']
    @auth = Auth.find_by(username: session['username'])
    if @auth and !@auth.key.to_s.empty? and !@auth.email.to_s.empty?
      @html = getBoard(@auth.key)
    end
  else
    redirect '/login', :notice => '请先登录!'
  end

  erb :index
end

get '/boards/:board_id' do
  @auth = Auth.find_by(username: session['username'])
  @html = getList(@auth.key, params['board_id'])

  erb :index
end

get '/lists/:list_id' do
  @auth = Auth.find_by(username: session['username'])
  @html = getCards(@auth.key, params['list_id'])

  erb :index
end

get '/card/:card_id' do
  @auth = Auth.find_by(username: session['username'])
  @html = getChecklist(@auth.key, params['card_id'])

  erb :index
end

post ('/') do
  if session['username']
    @auth = Auth.find_by(username: session['username'])
    if @auth
      @auth.key = params[:auth]['key'] if params[:auth]['key']
      @auth.email = params[:auth]['email'] if params[:auth]['email']
      @auth.real_name = params[:auth]['real_name'] if params[:auth]['real_name']
      if @auth.save
        redirect '/', :notice => 'Congrats! 记录已保存'
      end
    end
  end
end

get '/user/:name/send/:id' do


  if session['username']
    @auth = Auth.find_by(username: session['username'])
    if @auth

      @html = getChecklist(@auth.key, params['id'])
      email_body = erb :mail, layout: false, locals: {fields: @html}

      if @auth.email
        @auth.email.split(',').each do |email|
          sendWeekPost(email, "#{::CONF['Smtp']['user_name']}",
                      "#{@auth.real_name} 本周周报 #{takeFivedayRange[0]} -
                      #{takeFivedayRange[1]}", email_body)
        end
        redirect '/', :notice => '周报已发送成功!'
      else
        redirect '/', :error => '邮件列表不存在!'
      end
    end
  else
    redirect '/login', :notice => '请先登录!'
  end

end

get '/user/:name/remove_key' do
  if session['username'] == params['name']
    @auth = Auth.find_by(username: params['name'])
    if @auth
      @auth.key = ''
      if @auth.save
        redirect '/', :notice => 'Congrats! 您已成功移除Trello Token.'
      end
    end
  end
end

get '/user/:name/remove_realname' do
  if session['username'] == params['name']
    @auth = Auth.find_by(username: params['name'])
    if @auth
      @auth.real_name = ''
      if @auth.save
        redirect '/', :notice => 'Congrats! 您已成功移除显示名称.'
      end
    end
  end
end

get '/user/:name/remove_emails' do
  if session['username'] == params['name']
    @auth = Auth.find_by(username: params['name'])
    if @auth
      @auth.email = ''
      if @auth.save
        redirect '/', :notice => 'Congrats! 您已成功移除Email.'
      end
    end
  end
end
