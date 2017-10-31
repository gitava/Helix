defmodule Helix.Process.Model.Top.AllocatorTest do

  use ExUnit.Case, async: true

  import Helix.Test.Process.Macros

  alias Helix.Process.Model.Process
  alias Helix.Process.Model.TOP.Allocator, as: TOPAllocator

  alias Helix.Test.Process.Setup.TOP, as: TOPSetup

  alias HELL.TestHelper.Random

  describe "allocate/2" do

    test "one process; all resources" do
      {total_resources, _} = TOPSetup.Resources.resources()

      [proc1] =
        TOPSetup.fake_process(
          total_resources: total_resources, dynamic: [:cpu, :ram, :ulk, :dlk]
        )

      assert [{returned_proc, alloc}] =
        TOPAllocator.allocate(total_resources, [proc1])

      assert returned_proc == proc1

      # Allocation of one process will receive all available resources
      assert_resource alloc.cpu, total_resources.cpu
      assert_resource alloc.ram, total_resources.ram
      assert_resource alloc.dlk, total_resources.dlk
      assert_resource alloc.ulk, total_resources.ulk
    end

    test "two processes; non-overlapping dynamic; non-overlapping static" do
      {total_resources, _} = TOPSetup.Resources.resources()

      [proc1, proc2, proc3, proc4] =
        TOPSetup.fake_process(total_resources: total_resources, total: 4)

      # Proc1 has dynamic CPU resource and does not use any other static res
      proc1 = %{proc1| dynamic: [:cpu]}
      proc1 = put_in(proc1, [:static, :running, :ram], 0)
      proc1 = put_in(proc1, [:static, :running, :ulk], 0)
      proc1 = put_in(proc1, [:static, :running, :dlk], 0)

      # Proc2 has dynamic RAM resource and does not use any other static res
      proc2 = %{proc2| dynamic: [:ram]}
      proc2 = put_in(proc2, [:static, :running, :cpu], 0)
      proc2 = put_in(proc2, [:static, :running, :ulk], 0)
      proc2 = put_in(proc2, [:static, :running, :dlk], 0)

      # Proc3 has dynamic ULK resource and does not use any other static res
      proc3 = %{proc3| dynamic: [:ulk]}
      proc3 = put_in(proc3, [:static, :running, :cpu], 0)
      proc3 = put_in(proc3, [:static, :running, :ram], 0)
      proc3 = put_in(proc3, [:static, :running, :dlk], 0)

      # Proc4 has dynamic DLK resource and does not use any other static res
      proc4 = %{proc4| dynamic: [:dlk]}
      proc4 = put_in(proc4, [:static, :running, :cpu], 0)
      proc4 = put_in(proc4, [:static, :running, :ram], 0)
      proc4 = put_in(proc4, [:static, :running, :ulk], 0)

      procs = [proc1, proc2, proc3, proc4]

      assert [{p1, alloc1}, {p2, alloc2}, {p3, alloc3}, {p4, alloc4}] =
        TOPAllocator.allocate(total_resources, procs)

      assert p1 == proc1
      assert p2 == proc2
      assert p3 == proc3
      assert p4 == proc4

      # Allocated all available server resources
      assert_resource alloc1.cpu, total_resources.cpu
      assert_resource alloc1.ram, 0
      assert_resource alloc1.ulk, 0
      assert_resource alloc1.dlk, 0

      assert_resource alloc2.cpu, 0
      assert_resource alloc2.ram, total_resources.ram
      assert_resource alloc2.ulk, 0
      assert_resource alloc2.dlk, 0

      assert_resource alloc3.cpu, 0
      assert_resource alloc3.ram, 0
      assert_resource alloc3.ulk, total_resources.ulk
      assert_resource alloc3.dlk, 0

      assert_resource alloc4.cpu, 0
      assert_resource alloc4.ram, 0
      assert_resource alloc4.ulk, 0
      assert_resource alloc4.dlk, total_resources.dlk
    end

    test "two processes; non-overlapping dynamic; overlapping static" do
      {total_resources, _} = TOPSetup.Resources.resources()

      # Note that, by default, all processes have *some* static res assigned to
      # it (except dlk/ulk).
      [proc1, proc2] =
        TOPSetup.fake_process(total_resources: total_resources, total: 2)

      # `proc1` will be dynamic only on CPU; `proc2`, on RAM
      proc1 = %{proc1| dynamic: [:cpu]}
      proc2 = %{proc2| dynamic: [:ram]}

      procs = [proc1, proc2]

      assert [{p1, alloc1}, {p2, alloc2}] =
        TOPAllocator.allocate(total_resources, procs)

      assert p1 == proc1
      assert p2 == proc2

      # Allocated all available server resources
      assert_resource alloc1.cpu + alloc2.cpu, total_resources.cpu
      assert_resource alloc1.ram + alloc2.ram, total_resources.ram
    end

    test "two processes; overlapping dynamic and static resources" do
      {total_resources, _} = TOPSetup.Resources.resources()

      procs = TOPSetup.fake_process(
        total_resources: total_resources, total: 2, dynamic: [:cpu, :ram]
      )

      assert [{_p1, alloc1}, {_p2, alloc2}] =
        TOPAllocator.allocate(total_resources, procs)

      # Allocated all available server resources
      assert_resource alloc1.cpu + alloc2.cpu, total_resources.cpu
      assert_resource alloc1.ram + alloc2.ram, total_resources.ram
    end

    test "n processes; overlapping everywhere" do
      {total_resources, _} = TOPSetup.Resources.resources()
      initial = Process.Resources.initial()

      # We'll simulate the allocation of 50..100 processes (it takes 3ms!)
      n = Random.number(min: 50, max: 100)

      procs =
        TOPSetup.fake_process(
          total_resources: total_resources, total: n, dynamic: [:cpu, :ram]
        )

      # Allocates all `n` processes
      results = TOPAllocator.allocate(total_resources, procs)

      accumulated_resources =
        Enum.reduce(results, initial, fn {_process, alloc}, acc ->
          Process.Resources.sum(acc, alloc)
        end)

      # The accumulation (sum) of all processes' resources must be equal to the
      # total server's resources.
      assert_resource accumulated_resources.cpu, total_resources.cpu
      assert_resource accumulated_resources.ram, total_resources.ram
    end

    test "rejects when there would be resource overflow (on static alloc)" do
      initial = Process.Resources.initial()

      [proc] = TOPSetup.fake_process()

      assert {:error, reason, _} = TOPAllocator.allocate(initial, [proc])
      assert reason == :resources
    end

    test "rejects when there would be overflow of DLK/ULK" do
      {total_resources, _} = TOPSetup.Resources.resources(network_id: :net)

      [proc] = TOPSetup.fake_process(network_id: :net)

      total_resources =
        total_resources
        |> put_in([:dlk, :net], 0)
        |> put_in([:ulk, :net], 0)
        |> Map.replace(:cpu, proc.objective.cpu)
        |> Map.replace(:ram, proc.objective.ram)

      assert {:error, reason, _} =
        TOPAllocator.allocate(total_resources, [proc])
      assert reason == :resources
    end

    test "picks the heaviest process among multiple overflowing processes" do
      initial = Process.Resources.initial()
      [proc] = TOPSetup.fake_process()

      # One process which overflows on all resources
      assert {:error, :resources, [heaviest]} =
        TOPAllocator.allocate(initial, [proc])

      assert heaviest.process_id == proc.process_id

      # Let's increase the fun

      {total_resources, _} = TOPSetup.Resources.resources(network_id: :net)
      [proc1, proc2] =
        TOPSetup.fake_process(
          total_resources: total_resources, network_id: :net, total: 2,
          static_ulk: 0, static_dlk: 0
        )

      # Both `proc1` and `proc2` are overflowing. Notice `proc2` requires more
      # CPU power than `proc1`, hence it's the heaviest
      # Also note that all other resources are NOT overflowed
      proc1 =
        proc1
        |> Map.from_struct()
        |> put_in([:static, :running, :cpu], total_resources.cpu + 2)

      proc2 =
        proc2
        |> Map.from_struct()
        |> put_in([:static, :running, :cpu], total_resources.cpu + 3)

      assert {:error, :resources, [heaviest]} =
        TOPAllocator.allocate(total_resources, [proc1, proc2])

      assert heaviest.process_id == proc2.process_id

      # More more fun

      # Now we'll make `proc1` overflow on RAM. On this new scenario, `proc1`
      # is overflowing (RAM) and `proc2` is overflowing too (CPU)
      proc1 =
        proc1
        |> put_in([:static, :running, :ram], total_resources.ram)

      # Allocate will return both processes as heaviest, since each one
      # overflows a different resource
      assert {:error, :resources, heaviest} =
        TOPAllocator.allocate(total_resources, [proc1, proc2])

      assert length(heaviest) == 2

      # Now `proc1` consumes 1 MHz more than `proc2`, so it's the heaviest
      # process on both RAM and CPU consumption
      proc1 =
        proc1
        |> put_in([:static, :running, :cpu], total_resources.cpu + 4)

      # Allocator only returns one process
      assert {:error, :resources, [heaviest]} =
        TOPAllocator.allocate(total_resources, [proc1, proc2])

      assert heaviest.process_id == proc1.process_id

      # MOARRRR FUN
      # Now we'll overflow DLK and ULK resources, so we can test KV Behaviour

      # `proc1` overflows CPU and RAM (from above experiments), and now DLK too
      proc1 =
        proc1
        |> put_in([:static, :running, :dlk], total_resources.dlk.net + 2)

      # `proc2`, on the other hand, overflows on ULK
      proc2 =
        proc2
        |> put_in([:static, :running, :ulk], total_resources.ulk.net + 2)

      [proc3] = TOPSetup.fake_process(network_id: :net)

      # `proc3` is a valid process, which consumes no static resources but would
      # like to receive dynamic shares (if any are available).
      proc3 =
        proc3
        |> Map.from_struct()
        |> put_in([:static, :running, :cpu], 0)
        |> put_in([:static, :running, :ram], 0)
        |> put_in([:static, :running, :dlk], 0)
        |> put_in([:static, :running, :ulk], 0)

      # Returned `proc1` and `proc2` as overflowers (overflowed?)
      assert {:error, :resources, heaviest} =
        TOPAllocator.allocate(total_resources, [proc1, proc2, proc3])

      assert length(heaviest) == 2
    end

    test "does not allocate dyn resources on partially completed objectives" do
      {total_resources, _} = TOPSetup.Resources.resources(network_id: :net)

      [proc] = TOPSetup.fake_process(total_resources: total_resources)

      # The process has already processed enough RAM, but not enough CPU.
      # Excpet for static resources (see test below), dynamic resources of
      # already completed objectives must not be allocated, and instead should
      # be routed to another process
      proc =
        %{proc|
          processed: %{cpu: 0, ram: 100, ulk: %{net: 30}, dlk: %{}},
          objective: %{cpu: 50, ram: 99.9, ulk: %{net: 29.9}, dlk: %{net: 50}},
          dynamic: [:cpu, :ram, :dlk, :ulk],
          static: %{},
          network_id: :net
        }

      [{_p, alloc}] = TOPAllocator.allocate(total_resources, [proc])

      # Allocated the expected CPU for the process
      assert_resource alloc.cpu, total_resources.cpu

      # But did not allocate any ram to it, since it's been completed already
      assert alloc.ram == 0.0

      # Allocated all DLK in the world...
      assert_resource alloc.dlk, total_resources.dlk

      # But did not allocate any ULK, since it's been completed already
      assert alloc.ulk == %{net: 0.0}

      # `proc2` is a copy of `proc`, but it has never processed anything.
      # So, if we try to allocate both `proc` and `proc2` at the same time, the
      # Allocator should give 50% CPU to both, and 100% RAMA to `proc2`.
      # Same applies to DLK/ULK: both should receive half of DLK, while `proc2`
      # has full ULK access.
      proc2 = %{proc| processed: nil}

      assert [{p1, alloc1}, {p2, alloc2}] =
        TOPAllocator.allocate(total_resources, [proc, proc2])

      assert p1 == proc
      assert p2 == proc2

      # `proc` got 50% of CPU and no RAM
      assert_resource alloc1.cpu, total_resources.cpu / 2
      assert alloc1.ram == 0.0

      # `proc` got 50% of DLK and no ULK
      assert_resource alloc1.dlk, total_resources.dlk.net / 2
      assert alloc1.ulk.net == 0.0

      # `proc2` got 50% of CPU and 100% of RAM
      assert_resource alloc2.cpu, total_resources.cpu / 2
      assert_resource alloc2.ram, total_resources.ram

      # `proc2` got 50% of DLK and 100% of ULK
      assert_resource alloc2.dlk, total_resources.dlk.net / 2
      assert_resource alloc2.ulk, total_resources.ulk
    end

    test "allocates static resources even on partially completed objectives" do
      {total_resources, _} = TOPSetup.Resources.resources(network_id: :net)

      [proc] = TOPSetup.fake_process(total_resources: total_resources)

      # `proc` has already completed its RAM objective, but not the CPU one.
      # However, it is requested that `proc` has 20 units of RAM attached to it
      # when it's running, so we'll obey even though that specific objective has
      # been completed
      proc =
        %{proc|
          processed: %{cpu: 0, ram: 100, dlk: %{}, ulk: %{}},
          objective: %{cpu: 50, ram: 99.9, dlk: %{}, ulk: %{}},
          static: %{
            running: %{
              cpu: 10,
              ram: 20,
              ulk: Map.put(%{}, :net, 30),
              dlk: Map.put(%{}, :net, 40),
            }
          },
          network_id: :net
         }

      [{_p, alloc}] = TOPAllocator.allocate(total_resources, [proc])

      # Allocated all CPU to the process
      assert_resource alloc.cpu, total_resources.cpu

      # Allocated only the required static resources on RAM
      assert alloc.ram == proc.static.running.ram

      # # But did not allocate any ram to it, since it's in use
      # assert alloc.ram == 0.0
    end
  end
end
