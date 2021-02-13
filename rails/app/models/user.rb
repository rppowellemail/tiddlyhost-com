class User < ApplicationRecord
  # Include devise modules. Others available are:
  # :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :timeoutable, :trackable

  has_many :sites, dependent: :destroy
  belongs_to :plan
  validates_presence_of :name
end