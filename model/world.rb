# -*- coding: utf-8 -*-

module Plugin::Twitter
  class World < Diva::Model
    extend Gem::Deprecate

    register :twitter, name: "Twitterアカウント"

    field.string :id, required: true
    field.string :slug, required: true
    alias_method :name, :slug
    field.string :token, required: true
    field.string :secret, required: true

    def initialize(hash)
      super(hash)
      user_initialize
    end

    def twitter
      @twitter ||= MikuTwitter.new.tap do |ﾋｳｨｯﾋﾋｰ|
        ck, cs = Plugin.filtering(:twitter_default_api_keys, nil, nil)
        ﾋｳｨｯﾋﾋｰ.consumer_key = ck
        ﾋｳｨｯﾋﾋｰ.consumer_secret = cs
        ﾋｳｨｯﾋﾋｰ.a_token = token
        ﾋｳｨｯﾋﾋｰ.a_secret = secret
      end
    end

    # 自分のUserを返す。初回はサービスに問い合せてそれを返す。
    def user_obj
      self[:user] end
    alias to_user user_obj

    # 自分のユーザ名を返す。初回はサービスに問い合せてそれを返す。
    def idname
      self[:user].idname end
    alias :user :idname
    deprecate :user, "user_obj.idname", 2018, 05

    def icon
      user_obj.icon
    end

    def title
      user_obj.title
    end

    def to_h
      super.merge(user: {id: user_obj.id,
                         idname: user_obj.idname,
                         name: user_obj.name,
                         profile_image_url: user_obj.icon.perma_link.to_s})
    end

    def path
      "/#{slug}"
    end

    # サービスにクエリ _kind_ を投げる。
    # レスポンスを受け取るまでブロッキングする。
    # レスポンスを返す。失敗した場合は、apifailイベントを発生させてnilを返す。
    # 0.1: このメソッドはObsoleteです
    def scan(kind=:friends_timeline, args={})
      no_mainthread
      wait = Queue.new
      __send__(kind, args).next{ |res|
        wait.push res
      }.terminate.trap{
        wait.push nil
      }
      wait.pop
    end

    # scanと同じだが、別スレッドで問い合わせをするのでブロッキングしない。
    # レスポンスが帰ってきたら、渡されたブロックが呼ばれる。
    # ブロックは、必ずメインスレッドで実行されることが保証されている。
    # Deferredを返す。
    # 0.1: このメソッドはObsoleteです
    def call_api(api, args = {}, &block)
      __send__(api, args).next(&block)
    end

    # Streaming APIに接続する
    def streaming(method = :userstream, *args, &proc)
      twitter.__send__(method, *args, &proc)
    end

    # なんかコールバック機能つける
    # Deferred返すから無くてもいいんだけどねー
    # 2017/4/15追記 これを書いた当時の俺氏ねや
    def self.define_postal(method, twitter_method = method, &wrap)
      function = lambda{ |api, options, &callback|
        if(callback)
          callback.call(:start, options)
          callback.call(:try, options)
          api.call(options).next{ |res|
            callback.call(:success, res)
            res
          }.trap{ |exception|
            callback.call(:err, exception)
            callback.call(:fail, exception)
            callback.call(:exit, nil)
            Deferred.fail(exception)
          }.next{ |val|
            callback.call(:exit, nil)
            val }
        else
          api.call(options) end }
      if block_given?
        define_method(method){ |*args, &callback|
          wrap.call(lambda{ |options|
                      function.call(twitter.method(twitter_method), options, &callback) }, self, *args)
        }
      else
        define_method(method){ |options, &callback| function.call(twitter.method(twitter_method), options, &callback) }
      end
    end

    define_postal(:update){ |parent, service, options|
      parent.call(options).next{ |message|
        Plugin.call(:posted, service, [message])
        Plugin.call(:update, service, [message])
        message } }
    define_postal(:retweet){ |parent, service, options|
      parent.call(options).next{ |message|
        Plugin.call(:posted, service, [message])
        Plugin.call(:update, service, [message])
        message } }
    define_postal :search_create
    define_postal :search_destroy
    define_postal :follow
    define_postal :unfollow
    define_postal :add_list_member
    define_postal :delete_list_member
    define_postal :add_list
    define_postal :delete_list
    define_postal :update_list
    define_postal :send_direct_message
    define_postal :destroy_direct_message
    define_postal(:destroy){ |parent, service, options|
      parent.call(options).next{ |message|
        message[:rule] = :destroy
        Plugin.call(:destroyed, [message])
        message } }
    alias post update

    define_postal(:favorite) { |parent, service, message, fav = true|
      base = message.retweet? ? message[:retweet] : message
      if fav
        Plugin.call(:before_favorite, service, service.user_obj, base)
        parent.call(message).next{
          Plugin.call(:favorite, service, service.user_obj, base)
          base
        }.trap{ |e|
          Plugin.call(:fail_favorite, service, service.user_obj, base)
          Deferred.fail(e) }
      else
        service.unfavorite(message).next{
          Plugin.call(:unfavorite, service, service.user_obj, base)
          base } end }
    deprecate :favorite, "spell (see: https://reference.mikutter.hachune.net/reference/2017/11/28/spell.html#favorite-twitter-twitter_tweet)", 2018, 12

    define_postal :unfavorite

    def postable?(target=nil)
      Plugin[:twitter].compose?(self, target)
    end
    deprecate :postable?, "spell (see: https://reference.mikutter.hachune.net/reference/2017/11/28/spell.html#compose-twitter)", 2018, 11

    def post(to: nil, message:, **kwrest)
      Plugin[:twitter].compose(self, to, body: message, **kwrest)
    end
    deprecate :post, "spell (see: https://reference.mikutter.hachune.net/reference/2017/11/28/spell.html#compose-twitter)", 2018, 11

    def inspect
      "#<#{self.class.to_s}: #{id.inspect} #{slug.inspect}>"
    end

    def method_missing(method_name, *args)
      result = twitter.__send__(method_name, *args)
      (class << self; self end).__send__(:define_method, method_name, &twitter.method(method_name))
      result
    end

    # :nodoc:
    # 内部で利用するために用意されています。
    # ツイートを投稿したい場合は、
    # https://reference.mikutter.hachune.net/reference/2017/11/28/spell.html#compose-twitter
    # を参照してください。
    def post_tweet(options)
      twitter.update(options).next{ |message|
        Plugin.call(:posted, self, [message])
        Plugin.call(:update, self, [message])
        message
      }
    end

    # :nodoc:
    def post_dm(options)
      twitter.send_direct_message(options).next do |dm|
        Plugin.call(:direct_messages, self, [dm])
        dm
      end
    end

    private

    def user_initialize
      if self[:user]
        self[:user] = Plugin::Twitter::User.new_ifnecessary(self[:user])
        run_once(self[:user]) { (twitter/:account/:verify_credentials).user }
          .next(&method(:user_data_received))
          .trap(&method(:user_data_failed))
          .terminate
      else
        res = twitter.query!('account/verify_credentials', cache: true)
        if "200" == res.code
          user_data_received(MikuTwitter::ApiCallSupport::Request::Parser.user(JSON.parse(res.body).symbolize))
        else
          user_data_failed_crash!(res)
        end
      end
    end

    def user_data_received(user)
      # user_initializeはrun_onceでUser ID毎に結果がキャッシュされ、起動後2回目以降の正常系では同じオブジェクトがここに来る。
      # その時は処理がループしてしまうので、Worldを更新しない。
      unless self[:user].equal?(user)
        self[:user] = user
        Plugin.call(:world_modify, self)
      end
    end

    def user_data_failed(exception)
      case exception
      when MikuTwitter::Error
        if not UserConfig[:verify_credentials]
          user_data_failed_crash!(exception.httpresponse)
        end
      else
        raise exception
      end
    end

    def user_data_failed_crash!(res)
      if '400' == res.code
        chi_fatal_alert "起動に必要なデータをTwitterが返してくれませんでした。規制されてるんじゃないですかね。\n" +
                        "ニコ動とか見て、規制が解除されるまで適当に時間を潰してください。ヽ('ω')ﾉ三ヽ('ω')ﾉもうしわけねぇもうしわけねぇ\n" +
                        "\n\n--\n\n" +
                        "#{res.code} #{res.body}"
      else
        chi_fatal_alert "起動に必要なデータをTwitterが返してくれませんでした。電車が止まってるから会社行けないみたいなかんじで起動できません。ヽ('ω')ﾉ三ヽ('ω')ﾉもうしわけねぇもうしわけねぇ\n"+
                        "Twitterサーバの情況を調べる→ https://dev.twitter.com/status\n"+
                        "Twitterサーバの情況を調べたくない→ http://ex.nicovideo.jp/vocaloid\n\n--\n\n" +
                        "#{res.code} #{res.body}"
      end
    end

    # userごとに一度だけブロックを評価し、deferredを返す。
    # 2回目以降はブロックの評価はせず、最初の呼び出しと実行結果を共有するdeferredを生成して返す。
    def run_once(user, &block)
      @@run_once_mutex ||= Mutex.new
      @@run_once_deferred_by_userid ||= {}
      @@run_once_mutex.synchronize do
        trunk = @@run_once_deferred_by_userid[user.id] || block.call
        branch = @@run_once_deferred_by_userid[user.id] = Delayer::Deferred.new(true)
        trunk.next { |v| branch.call(v); v }
          .trap { |v| branch.fail(v); Delayer::Deferred.fail(v) }
      end
    end
  end
end
