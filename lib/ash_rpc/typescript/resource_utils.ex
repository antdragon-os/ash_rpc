defmodule AshRpc.TypeScript.ResourceUtils do
  @moduledoc """
  Utility functions for resource inspection and processing.
  """

  @doc """
  Gets all resources for aliases generation from the given domains.
  """
  def get_resources_for_aliases(domains) do
    domains
    |> Enum.flat_map(fn domain ->
      Ash.Domain.Info.resources(domain)
      |> Enum.filter(&exposed_resource?/1)
    end)
    |> Enum.uniq()
  end

  @doc """
  Checks if a resource is exposed for generation.
  """
  def exposed_resource?(resource) do
    case AshRpc.Dsl.Info.expose(resource) do
      nil -> false
      _ -> true
    end
  rescue
    _ -> false
  end

  @doc """
  Checks if an action is exposed for generation.
  """
  def exposed_action?(resource, act) do
    AshRpc.Dsl.Info.exposed?(resource, act.name)
  rescue
    _ -> false
  end

  @doc """
  Gets the resource segment name for URL generation.
  """
  def resource_segment(resource) do
    AshRpc.Dsl.Info.resource_name(resource) ||
      resource |> Module.split() |> List.last() |> Macro.underscore()
  end

  @doc """
  Gets the domain segment name for URL generation.
  """
  def domain_segment(domain) do
    domain |> Module.split() |> List.last() |> Macro.underscore()
  end

  @doc """
  Safely gets procedures from a resource.
  """
  def safe_procedures(resource) do
    try do
      AshRpc.Dsl.Info.procedures(resource)
    rescue
      _ -> []
    end
  end

  @doc """
  Finds a router module that exposes domains/0 function.
  """
  def find_router_module do
    # find modules that have a `domains/0` function (from AshRpc.Router __using__)
    modules = :code.all_loaded() |> Enum.map(&elem(&1, 0))

    routers =
      Enum.filter(modules, fn mod ->
        function_exported?(mod, :domains, 0)
      end)

    case routers do
      [] -> {:error, "No router module with domains/0 found. Pass --domains"}
      [router | _] -> {:ok, router.domains()}
      _ -> {:ok, hd(routers).domains()}
    end
  end
end
