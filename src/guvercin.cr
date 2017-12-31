require "./models/*"
require "./guvercin/*"
require "kemal"
require "kemal-session"
require "db"
require "pg"

public_folder "src/assets"

module Guvercin
  SOCKETS      = {} of String => Array(HTTP::WebSocket)
  database_url = "postgres://anil@localhost:5432/guvercin"
  db           = DB.open(database_url)

  Kemal::Session.config do |config|
    config.cookie_name = "81750878"
    config.secret      = "16ab2a8882f31578b184fc29"
    config.gc_interval = 2.minutes
  end

  def authorized?(env)
    env.session.string?("email")
  end

  ws "/chat/:conversation_id" do |socket, env|
    conversation_id = env.params.url["conversation_id"]

    if SOCKETS.has_key?(conversation_id)
      SOCKETS[conversation_id] << socket
    else
      SOCKETS[conversation_id] = [socket]
    end

    socket.on_message do |b|
      body = [] of String | Int32
      body = b.split("=:=")

      SOCKETS[conversation_id].each do |socket|
        socket.send body[0]
      end

      db.exec("insert into messages(body, user_id, conversation_id) values($1::text, $2::integer, $3::integer)", body[0], body[1], body[3])
      db.close
    end

    socket.on_close do
      SOCKETS.delete(conversation_id)
    end
  end

  get "/" do |env|
    render "src/views/layouts/home.ecr", "src/views/layouts/layout.ecr"
  end

  get "/users/:id/messages" do |env|
    if env.session.string?("email") && env.session.string?("id")
      id            = env.params.url["id"].to_i
      messages      = [] of Hash(String, String | Int32)
      user          = {} of String => String | Int32
      current_user  = {} of String => String | Int32

      user["id"], user["email"] = db.query_one("select id, email from users where id = $1::int", id, as: {Int32, String})
      current_user["id"]    = env.session.string("id")
      current_user["email"] = env.session.string("email")

      conversation_id = db.query_one("select id from conversations where (sender_id = $1::int and receiver_id = $2::int) or (sender_id = $2::int and receiver_id = $1::int)", id, current_user["id"], as: {Int32})

      db.query("select body, user_id from messages where conversation_id = $1::int order by id desc limit 10", conversation_id) do |rs|
        rs.each do
          message            = {} of String => String | Int32
          message["body"]    = rs.read(String)
          message["user_id"] = rs.read(Int32)
          messages << message
        end
      end

      render "src/views/messages/index.ecr", "src/views/layouts/layout.ecr"
    else
      env.redirect "/"
    end
  end

  get "/users" do |env|
    if env.session.string?("email") && env.session.string?("id")
      users = [] of Hash(String, String | Int32)

      db.query("select id, email from users") do |rs|
        rs.each do
          user          = {} of String => String | Int32
          user["id"]    = rs.read(Int32)
          user["email"] = rs.read(String)
          users << user
        end
      end
      db.close

      render "src/views/users/index.ecr", "src/views/layouts/layout.ecr"
    else
      env.redirect "/"
    end
  end

  get "/users/:id" do |env|
    user = {} of String => String | Int32
    id   = env.params.url["id"]

    user["id"], user["email"] = db.query_one("select id, email from users where id = $1::int", id, as: {Int32, String})
    db.close

    render "src/views/users/show.ecr", "src/views/layouts/layout.ecr"
  end

  get "/signup" do |env|
    render "src/views/layouts/signup.ecr", "src/views/layouts/layout.ecr"
  end

  get "/login" do |env|
    render "src/views/layouts/login.ecr", "src/views/layouts/layout.ecr"
  end

  post "/signup" do |env|
    params = [] of String

    params << env.params.body["email"]
    params << env.params.body["code"]

    db.exec("insert into users(email, code) values($1::text, $2::text)", params)
    db.close

    env.redirect "/login"
  end

  post "/logout" do |env|
    env.session.destroy
    env.redirect "/"
  end

  post "/login" do |env|
    params = [] of String
    user   = {} of String => String | Int32

    params << env.params.body["email"]
    params << env.params.body["code"]

    user["id"], user["email"] = db.query_one("select id, email from users where email = $1::text", params[0], as: {Int32, String})
    env.session.string("email", user["email"].to_s)
    env.session.string("id", user["id"].to_s)
    db.close

    env.redirect "/users"
  end
end

Kemal.run
