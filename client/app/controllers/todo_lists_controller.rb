# frozen_string_literal: true

require 'grpc'
require 'todo_service_services_pb'

class TodoListsController < ApplicationController

  def index
    if request.format.html?
      render :index
    else
      request = TodoService::ListTasksRequest.new
      tasks = stub.list_tasks(request).map do |response|
        { id: response.id, description: response.description, completed: response.completed }
      end
      render json: { data: tasks }
    end
  end

  def show
    request = TodoService::GetTaskRequest.new(id: params[:id])
    response = stub.get_task(request)
    render json: { data: { id: response.id, description: response.description, completed: response.completed, serialized_task: response.serialized_task.unpack1('H*') } }
  rescue GRPC::NotFound
    render json: { error: 'Task not found' }, status: :not_found
  end

  def create
    request = TodoService::AddTaskRequest.new(
      description: params[:description],
      completed: params[:completed] || false
    )
    response = stub.add_task(request)
    render json: { data: { id: response.id, serialized_task: response.serialized_task.unpack1('H*') } }, status: :created
  rescue GRPC::BadStatus => e
    render json: { error: e.message }, status: :bad_request
  end

  def bulk_create
    requests = params[:tasks].map do |task|
      TodoService::AddTasksBulkRequest.new(
        description: task[:description],
        completed: task[:completed] || false
      )
    end
    response = stub.add_tasks_bulk(requests.each)
    render json: { data: { count: response.count } }, status: :created
  rescue GRPC::BadStatus => e
    render json: { error: e.message }, status: :bad_request
  end


  def destroy
    puts params[:id]  
    request = TodoService::DeleteTaskRequest.new(id: params[:id].to_i)
    response = stub.delete_task(request)
    render json: { data: { id: response.id } }, status: :ok
  rescue GRPC::NotFound => e
    render json: { error: 'Task not found' }, status: :not_found
  end

  private

  def stub
    ::TodoService::TodoService::Stub.new('grpc-server:50051', :this_channel_is_insecure)
  rescue GRPC::BadStatus => e
    render json: { error: e.message }, status: :bad_request
  end
end
