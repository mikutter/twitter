# -*- coding: utf-8 -*-

=begin rdoc
Twitter APIとmikutterプラグインのインターフェイス
=end
module Service
  extend Enumerable

  class << self

    # 存在するServiceオブジェクトを全て返す。
    # つまり、投稿権限のある「自分」のアカウントを全て返す。
    # ==== Return
    # [Array] アカウントを示すDiva::Modelを各要素に持った配列。
    def instances
      Enumerator.new{|y|
        Plugin.filtering(:worlds, y)
      }.select{|world|
        world.class.slug == :twitter
      }
    end
    alias services instances

    # Service.instances.eachと同じ
    def each(*args, &proc)
      instances.each(*args, &proc) end

    # 現在アクティブになっているサービスを返す。
    # 基本的に、あるアクションはこれが返すアカウントに対して行われなければならない。
    # ==== Return
    # アクティブなアカウントに対応するModelか、存在しない場合はnil
    def primary
      world, = Plugin.filtering(:world_current, nil)
      world
    end
    alias primary_service primary

    # 現在アクティブになっているサービスを返す。
    # Service.primary とちがって、サービスが一つも登録されていない時、例外を発生させる。
    # ==== Exceptions
    # Plugin::World::NotExistError :: (選択されている)Serviceが存在しない
    # ==== Return
    # アクティブなService
    def primary!
      result = primary
      raise Plugin::World::NotExistError, 'World does not exists.' unless result
      result
    end

    def set_primary(service)
      Plugin.call(:world_change_current, service)
      self
    end

    def destroy(service)
      Plugin.call(:world_destroy, service)
    end
    def remove_service(service)
      destroy(service) end
  end
end

Post = Service
