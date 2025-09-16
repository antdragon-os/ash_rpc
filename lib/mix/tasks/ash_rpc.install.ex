if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshRpc.Install do
    @shortdoc "Installs AshRpc into a Phoenix project"
    @moduledoc """
    Installs AshRpc into the current Phoenix project:

    - Generates `YourAppWeb.TrpcRouter`
    - Adds `forward "/trpc", YourAppWeb.TrpcRouter` to your Phoenix router

    This task will modify your router.ex and create the tRPC router file.
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :ash
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      if Mix.Project.umbrella?() do
        Mix.raise("mix ash_rpc.install can only be run inside an application directory")
      end

      app_name = Atom.to_string(Mix.Project.config()[:app])
      web_module_name = Module.concat([Macro.camelize(app_name <> "_web")])
      trpc_router_module = Module.concat([web_module_name, TrpcRouter])

      # Check if AshAuthentication is available
      auth_enabled? = has_auth_dependency?()

      # Initialize status tracking
      status = %{created: [], skipped: [], updated: []}

      # Create the tRPC router module using Igniter with status tracking
      {igniter, status} = create_trpc_router_smart(igniter, trpc_router_module, status)

      # Update the router using a simple patch approach with status tracking
      {igniter, status} =
        update_router_with_patch_smart(
          igniter,
          web_module_name,
          trpc_router_module,
          auth_enabled?,
          app_name,
          status
        )

      # Report status to user
      report_status(status, trpc_router_module)

      igniter
    end

    defp create_trpc_router_smart(igniter, trpc_router_module, status) do
      app_name = Atom.to_string(Mix.Project.config()[:app])
      file_path = Path.join(["lib", "#{app_name}_web", "trpc_router.ex"])

      if File.exists?(file_path) do
        # File exists, check if it has the correct content
        case File.read(file_path) do
          {:ok, content} ->
            expected_content = """
            defmodule #{inspect(trpc_router_module)} do
              use AshRpc.Web.Router, domains: []
            end
            """

            if String.trim(content) == String.trim(expected_content) do
              {igniter,
               Map.update!(
                 status,
                 :skipped,
                 &[
                   "#{inspect(trpc_router_module)} module (already exists with correct content)"
                   | &1
                 ]
               )}
            else
              File.write!(file_path, expected_content)

              {igniter,
               Map.update!(
                 status,
                 :updated,
                 &["#{inspect(trpc_router_module)} module (updated existing content)" | &1]
               )}
            end

          {:error, _} ->
            {igniter, status}
        end
      else
        # File doesn't exist, create it
        igniter =
          Igniter.Project.Module.create_module(igniter, trpc_router_module, """
          use AshRpc.Web.Router, domains: []
          """)

        {igniter, Map.update!(status, :created, &["#{inspect(trpc_router_module)} module" | &1])}
      end
    end

    defp update_router_with_patch_smart(
           igniter,
           _web_module_name,
           trpc_router_module,
           auth_enabled?,
           app_name,
           status
         ) do
      # Construct router path manually to avoid Igniter API issues
      router_path = Path.join(["lib", "#{app_name}_web", "router.ex"])

      # Create the pipeline code
      pipeline_code = create_pipeline_code(auth_enabled?, app_name)

      # Create the scope code
      scope_code = create_scope_code(trpc_router_module)

      # Read and analyze the router file
      case File.read(router_path) do
        {:ok, content} ->
          {updated_content, pipeline_added?, scope_added?} =
            update_router_content_smart(content, pipeline_code, scope_code)

          if pipeline_added? or scope_added? do
            File.write!(router_path, updated_content)

            status =
              if pipeline_added?,
                do: Map.update!(status, :created, &["tRPC pipeline in router" | &1]),
                else: status

            status =
              if scope_added?,
                do: Map.update!(status, :created, &["tRPC route forwarding in router" | &1]),
                else: status

            {igniter, status}
          else
            {igniter,
             Map.update!(
               status,
               :skipped,
               &["Router configuration (already properly configured)" | &1]
             )}
          end

        {:error, reason} ->
          Mix.shell().error("Failed to read router file: #{:file.format_error(reason)}")
          {igniter, status}
      end
    end

    defp create_pipeline_code(auth_enabled?, app_name) do
      if auth_enabled? do
        """
        # Ash RPC pipeline - JSON only + Bearer auth via AshAuthentication
        pipeline :ash_rpc do
          plug :accepts, ["json"]
          # Enables bearer token auth; requires AshAuthentication (or ash_authenticator) configured
          plug :retrieve_from_bearer, :#{app_name}
          plug :set_actor, :user
        end
        """
      else
        """
        # Ash RPC pipeline - JSON only
        # If using AshAuthentication, you can enable bearer token auth:
        #   plug :retrieve_from_bearer, :#{app_name}
        #   plug :set_actor, :user
        pipeline :ash_rpc do
          plug :accepts, ["json"]
        end
        """
      end
    end

    defp create_scope_code(trpc_router_module) do
      """
      # Mount Ash RPC under the :ash_rpc pipeline
      scope "/trpc" do
        pipe_through :ash_rpc
        forward "/", #{inspect(trpc_router_module)}
      end
      """
    end

    defp update_router_content_smart(content, pipeline_code, scope_code) do
      {content, pipeline_added} = add_pipeline_if_missing_smart(content, pipeline_code)
      {content, scope_added} = add_scope_if_missing_smart(content, scope_code)
      {content, pipeline_added, scope_added}
    end

    defp add_pipeline_if_missing_smart(content, pipeline_code) do
      if String.contains?(content, "pipeline :ash_rpc do") do
        {content, false}
      else
        new_content =
          if String.contains?(content, "pipeline :api do") do
            String.replace(
              content,
              ~r/(  pipeline :api do\n.*?\n  end\n)/s,
              "\\1\n#{pipeline_code}"
            )
          else
            # Fallback: insert before the first scope
            String.replace(content, ~r/(  scope "\/")/, "#{pipeline_code}\n\n  \\1")
          end

        {new_content, true}
      end
    end

    defp add_scope_if_missing_smart(content, scope_code) do
      if String.contains?(content, "scope \"/trpc\"") do
        {content, false}
      else
        new_content =
          if String.contains?(content, "pipeline :ash_rpc do") do
            String.replace(
              content,
              ~r/(pipeline :ash_rpc do\n.*?\n  end\n)/s,
              "\\1\n#{scope_code}"
            )
          else
            # Fallback: append to end
            content <> "\n#{scope_code}"
          end

        {new_content, true}
      end
    end

    defp report_status(status, trpc_router_module) do
      Mix.shell().info("\nAshRpc installation complete!")
      Mix.shell().info("=============================")

      unless Enum.empty?(status.created) do
        Mix.shell().info("\n✅ Created:")

        Enum.each(Enum.reverse(status.created), fn item ->
          Mix.shell().info("  • #{item}")
        end)
      end

      unless Enum.empty?(status.updated) do
        Mix.shell().info("\n🔄 Updated:")

        Enum.each(Enum.reverse(status.updated), fn item ->
          Mix.shell().info("  • #{item}")
        end)
      end

      unless Enum.empty?(status.skipped) do
        Mix.shell().info("\n⏭️  Skipped:")

        Enum.each(Enum.reverse(status.skipped), fn item ->
          Mix.shell().info("  • #{item}")
        end)
      end

      Mix.shell().info("\n📝 Next steps:")

      Mix.shell().info(
        "  • Add your Ash domains to the #{inspect(trpc_router_module)} domains list"
      )

      Mix.shell().info("  • Configure your frontend to connect to /trpc")

      if Enum.empty?(status.created) and Enum.empty?(status.updated) do
        Mix.shell().info("\n✨ AshRpc is already fully configured!")
      end
    end

    defp has_auth_dependency? do
      deps = Mix.Project.config()[:deps] || []

      Enum.any?(deps, fn
        dep ->
          case dep do
            {name, _opts} when is_atom(name) -> name in [:ash_authentication, :ash_authenticator]
            name when is_atom(name) -> name in [:ash_authentication, :ash_authenticator]
            _ -> false
          end
      end)
    end
  end
else
  defmodule Mix.Tasks.AshRpc.Install do
    @shortdoc "Installs AshRpc into a Phoenix project"
    @moduledoc """
    Installs AshRpc into the current Phoenix project:

    - Generates `YourAppWeb.TrpcRouter`
    - Adds `forward "/trpc", YourAppWeb.TrpcRouter` to your Phoenix router

    This task will modify your router.ex and create the tRPC router file.
    """

    use Mix.Task

    @impl true
    def run(_args) do
      Mix.shell().error("""
      The task 'ash_rpc.install' requires igniter to be run.

      Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
