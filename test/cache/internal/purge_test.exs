defmodule Helix.Cache.Internal.PurgeTest do

  use Helix.Test.Case.Integration

  import Helix.Test.Case.Cache
  import Helix.Test.Case.ID

  alias Helix.Network.Internal.Network, as: NetworkInternal
  alias Helix.Cache.Internal.Cache, as: CacheInternal
  alias Helix.Cache.Internal.Populate, as: PopulateInternal
  alias Helix.Cache.Internal.Purge, as: PurgeInternal
  alias Helix.Cache.State.PurgeQueue, as: StatePurgeQueue

  alias Helix.Test.Network.Helper, as: NetworkHelper
  alias Helix.Test.Cache.Helper, as: CacheHelper

  @internet_id NetworkHelper.internet_id()

  setup do
    CacheHelper.cache_context()
  end

  # REMEMBER:
  # - PurgeInternal.update|purge is SYNCHRONOUS
  #   - (but side-population isn't)
  # - CacheInternal.update|purge is ASYNCHRONOUS
  #   - (but mark_as_purged/2 isn't)

  describe "update/2" do
    test "existing data is updated", context do
      server_id = context.server.server_id

      {:ok, _} = PopulateInternal.populate(:by_server, server_id)

      {:hit, server1} = CacheInternal.direct_query(:server, server_id)

      # Modify server ip
      nip = Enum.random(server1.networks)
      nc = NetworkInternal.Connection.fetch(@internet_id, nip["ip"])
      new_ip = HELL.IPv4.autogenerate()
      {:ok, _} = NetworkInternal.Connection.update_ip(nc, new_ip)

      StatePurgeQueue.sync()

      # Query again
      {:ok, server2} = CacheInternal.lookup(:server, server_id)

      # Ensure it is in the cache
      assert_hit CacheInternal.direct_query(:server, server_id)

      server2_ip = server2.networks
        |> Enum.random()
        |> Map.get(:ip)

      assert_miss CacheInternal.direct_query(
        :network,
        {nip["network_id"], nip["ip"]}
      )

      assert server1 != server2
      assert_id server1.server_id, server2.server_id
      refute nip["ip"] == server2_ip
      assert server2_ip == new_ip

      CacheHelper.sync_test()
    end

    test "populates non-existing data", context  do
      server_id = context.server.server_id

      # Ensure cache is empty
      CacheInternal.purge(:server, to_string(server_id))
      StatePurgeQueue.sync()

      assert_miss CacheInternal.direct_query(:server, server_id)
      refute StatePurgeQueue.lookup(:server, server_id)

      # Request server update
      CacheInternal.update(:server, to_string(server_id))

      # It's added to the queue
      assert StatePurgeQueue.lookup(:server, server_id)

      # But hasn't synced yet
      assert_miss CacheInternal.direct_query(:server, server_id)
      assert_miss CacheInternal.direct_query(:server, server_id)
      assert_miss CacheInternal.direct_query(:server, server_id)

      StatePurgeQueue.sync()

      refute StatePurgeQueue.lookup(:server, server_id)

      {:hit, server} = CacheInternal.direct_query(:server, server_id)

      assert_id server.server_id, server_id

      CacheHelper.sync_test()
    end
  end

  describe "purge/2" do
    test "obliterates objects from DB", context do
      server_id = context.server.server_id

      {:ok, server} = PopulateInternal.populate(:by_server, server_id)

      nip = Enum.random(server.networks)
      storage_id = Enum.random(server.storages)

      # Purge nip
      PurgeInternal.purge(:network, {nip.network_id, nip.ip})
      assert_miss CacheInternal.direct_query(:network, {nip.network_id, nip.ip})

      # Purging nip shouldn't affect others
      {:hit, _} = CacheInternal.direct_query(:storage, storage_id)
      {:hit, _} = CacheInternal.direct_query(:server, server_id)

      # Purging storage
      PurgeInternal.purge(:storage, {storage_id})
      assert_miss CacheInternal.direct_query(:storage, storage_id)

      # Purging storage shouldn't affect others
      {:hit, _} = CacheInternal.direct_query(:server, server_id)

      CacheHelper.sync_test()
    end
  end
end
