actions :set
default_action :set

attribute :name, :kind_of => String, :name_attribute => true

attribute :values, :kind_of => Hash, :required => true
attribute :instance, :kind_of => Hash, :required => true
attribute :delayed, :default => true
