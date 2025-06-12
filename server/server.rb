require 'grpc'
require 'json'
require 'fileutils'
require_relative 'lib/todo_service_services_pb'

class TodoStore
  def initialize(file_path = 'tasks.json')
    @file_path = file_path
    unless File.exist?(@file_path)
      File.write(@file_path, JSON.pretty_generate({ last_id: 0, tasks: [] }))
    end
  end

  def add(task)
    File.open(@file_path, 'r+') do |file|
      file.flock(File::LOCK_EX)
      data = JSON.parse(file.read, symbolize_names: true)
      last_id = data[:last_id] || 0
      task[:id] = last_id + 1
      data[:tasks] << task
      data[:last_id] = task[:id]
      file.rewind
      file.write(JSON.pretty_generate(data))
    end
    task[:id]
  end

  def all
    File.open(@file_path, 'r') do |file|
      file.flock(File::LOCK_SH)
      JSON.parse(file.read, symbolize_names: true)[:tasks] || []
    end
  rescue JSON::ParserError
    puts "Invalid JSON in #{@file_path}, returning empty array"
    []
  end

  def find(id)
    all.find { |t| t[:id] == id }
  end

  def update(id, completed)
    File.open(@file_path, 'r+') do |file|
      file.flock(File::LOCK_EX)
      data = JSON.parse(file.read, symbolize_names: true)
      task = data[:tasks].find { |t| t[:id] == id }
      if task
        task[:completed] = completed
        file.rewind
        file.write(JSON.pretty_generate(data))
        file.truncate(file.pos)
        puts "Updated task id=#{id} to completed=#{completed}"
      end
    end
  end

  def delete(id)
    File.open(@file_path, 'r+') do |file|
      file.flock(File::LOCK_EX)
      data = JSON.parse(file.read, symbolize_names: true)
      if data[:tasks].any? { |t| t[:id] == id }
        data[:tasks].reject! { |t| t[:id] == id }
        file.rewind
        file.write(JSON.pretty_generate(data))
        file.truncate(file.pos)
        return true
      end
      false
    end
  end
end

class TodoServiceImpl < TodoService::TodoService::Service
  def initialize
    @store = TodoStore.new
  end

  def add_task(request, _call)
    task = { description: request.description, completed: request.completed }
    id = @store.add(task)
    serialized = JSON.dump(task.merge(id: id)).b
    TodoService::AddTaskResponse.new(id: id, serialized_task: serialized)
  end

  def add_tasks_bulk(call)
    count = 0
    call.each_remote_read do |request|
      task = { description: request.description, completed: request.completed }
      @store.add(task)
      count += 1
      sleep 0.5
    end
    TodoService::AddTasksBulkResponse.new(count: count)
  end

  def list_tasks(request, _call)
    puts "Listing tasks with completion status: #{request.completed}"
    @store.all.lazy.map do |task|
      TodoService::ListTasksResponse.new(
        id: task[:id],
        description: task[:description],
        completed: task[:completed]
      )
    end
  end

  def update_task_statuses(_call)
    Enumerator.new do |y|
      requests.each do |request|
        @store.update(request.id, request.completed)
        task = @store.find(request.id)
        if task
          serialized = JSON.dump(task).b
          y << TodoService::UpdateTaskStatusResponse.new(
            id: request.id,
            completed: request.completed,
            serialized_task: serialized
          )
        end
        sleep 0.5
      end
    end
  end

  def delete_task(request, _call)
    if @store.delete(request.id)
      TodoService::DeleteTaskResponse.new(id: request.id)
    else
      raise GRPC::NotFound, "Task id=#{request.id} not found"
    end
  end

  def get_task(request, _call)
    task = @store.find(request.id)
    if task
      serialized = JSON.dump(task).b
      TodoService::GetTaskResponse.new(
        id: task[:id],
        description: task[:description],
        completed: task[:completed],
        serialized_task: serialized
      )
    else
      raise GRPC::NotFound, "Task id=#{request.id} not found"
    end
  end
end

def start_grpc_server
  port = '0.0.0.0:50051'
  s = GRPC::RpcServer.new
  s.add_http2_port(port, :this_port_is_insecure)
  s.handle(TodoServiceImpl)
  s.run_till_terminated
end

start_grpc_server
