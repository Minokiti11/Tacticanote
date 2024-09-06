class Practice < ApplicationRecord
    belongs_to :group, optional: true
    belongs_to :user, optional: true

    has_rich_text :content

    validates :links, format: { with: URI::regexp(%w[http https]), message: "有効なURLを入力してください" }, allow_blank: true
end
