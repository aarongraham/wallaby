defmodule Wallaby.Experimental.Chrome.Chromedriver.Server do
  @moduledoc false
  use GenServer

  alias Wallaby.Driver.Utils
  alias Wallaby.Experimental.Chrome.Chromedriver.ReadinessChecker

  defmodule State do
    @moduledoc false
    defstruct [:port_number, :chromedriver_path, ready?: false, calls_awaiting_readiness: []]

    @type port_number :: non_neg_integer

    @type t :: %__MODULE__{
            port_number: port_number | nil,
            chromedriver_path: String.t(),
            calls_awaiting_readiness: [GenServer.from()]
          }
  end

  @type server :: GenServer.server()
  @typep port_number :: non_neg_integer()

  @default_startup_timeout :timer.seconds(10)

  def child_spec(args) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, args}}
  end

  @type start_link_opt :: {:startup_timeout, timeout()} | GenServer.option()

  @spec start_link(String.t(), [start_link_opt]) :: GenServer.on_start()
  def start_link(chromedriver_path, opts \\ [])
      when is_binary(chromedriver_path) and is_list(opts) do
    {start_opts, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, {chromedriver_path, opts}, start_opts)
  end

  @spec get_base_url(server) :: String.t()
  def get_base_url(server) do
    server
    |> GenServer.call(:get_port_number)
    |> build_base_url()
  end

  @spec wait_until_ready(server, timeout()) :: :ok | {:error, :timeout}
  def wait_until_ready(server, timeout \\ 5000) do
    GenServer.call(server, :wait_until_ready, timeout)
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}
  end

  @impl true
  def init({chromedriver_path, opts}) do
    port_number = Utils.find_available_port()
    base_url = build_base_url(port_number)

    open_chromedriver_port(chromedriver_path, port_number)
    ReadinessChecker.wait_until_ready(base_url)

    {:ok, %State{chromedriver_path: chromedriver_path, port_number: port_number}}
  end

  @impl true
  def handle_call(:get_port_number, _from, %State{port_number: port_number} = state) do
    {:reply, port_number, state}
  end

  @spec open_chromedriver_port(String.t(), port_number) :: port
  def open_chromedriver_port(chromedriver_path, port_number) when is_binary(chromedriver_path) do
    Port.open(
      {:spawn_executable, to_charlist(wrapper_script())},
      port_opts(chromedriver_path, port_number)
    )
  end

  @spec wrapper_script :: String.t()
  defp wrapper_script do
    Path.absname("priv/run_command.sh", Application.app_dir(:wallaby))
  end

  defp args(chromedriver, port),
    do: [
      chromedriver,
      "--log-level=OFF",
      "--port=#{port}"
    ]

  defp port_opts(chromedriver, tcp_port),
    do: [
      :binary,
      :stream,
      :use_stdio,
      :stderr_to_stdout,
      :exit_status,
      args: args(chromedriver, tcp_port)
    ]

  @spec build_base_url(port_number) :: String.t()
  defp build_base_url(port_number) do
    "http://localhost:#{port_number}/"
  end
end
