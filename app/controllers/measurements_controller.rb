class MeasurementsController < ApplicationController

  include Seek::IndexPager

  before_action :measurements_enabled?
  before_action :find_assets, :only => [:index]
  before_action :find_and_authorize_requested_item, :except => [:index, :new, :create]
  before_action :project_membership_required, only: [:create, :new]


  def show
    @measurement
  end

  def new
    @measurement = Measurement.new
  end

  def create
    @measurement = Measurement.new(measurement_params)
    @measurement.contributor = current_user.person

    if @measurement.save
      flash[:notice] = "Measurement was successfully created."
      redirect_to @measurement
    else
      render action: 'new'
    end
  end

  def edit
  end

  def update
    update_annotations(params[:tag_list], @measurement) if params.key?(:tag_list)

    respond_to do |format|
      if @measurement.update(measurement_params)
        flash[:notice] = "Measurement was successfully updated."
        format.html { redirect_to @measurement }
      else
        format.html { render action: 'edit' }
      end
    end
  end

  def manage
    @measurement
  end

  def manage_update
    @measurement.attributes = measurement_params
    update_sharing_policies @measurement

    respond_to do |format|
      if @measurement.save
        flash[:notice] = "Measurement was successfully updated."
        format.html { redirect_to @measurement }
      else
        format.html { render action: 'manage' }
      end
    end
  end

  def destroy
    respond_to do |format|
      if @measurement.destroy
        flash[:notice] = "Measurement was successfully deleted."
        format.html { redirect_to measurements_path }
      else
        flash[:error] = "Failed to delete measurement"
        format.html { redirect_to @measurement }
      end
    end
  end

  private

  def find_and_authorize_requested_item
    @measurement = Measurement.find(params[:id])
    unless @measurement.can_view?(current_user)
      error('You do not have permission to view this measurement')
    end
  end

  def measurement_params
    params.require(:measurement).permit(:title, :description, :study_id, project_ids: []).tap do |p|
      # Remove blank project_ids that come from the hidden field
      p[:project_ids] = p[:project_ids]&.reject(&:blank?) if p[:project_ids]
    end
  end
end

