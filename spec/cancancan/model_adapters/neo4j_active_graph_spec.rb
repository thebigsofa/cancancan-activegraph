require 'spec_helper'
require 'support/shared_context_support'

if defined? CanCan::ModelAdapters::ActiveGraphAdapter

  describe CanCan::ModelAdapters::ActiveGraphAdapter do
    before :each do
      ActiveGraph::Base.label_object(Article.mapped_label_names.first).create_constraint(Article.id_property_name, type: :unique)
      ActiveGraph::Base.label_object(Category.mapped_label_names.first).create_constraint(Category.id_property_name, type: :unique)
      ActiveGraph::Base.label_object(Comment.mapped_label_names.first).create_constraint(Comment.id_property_name, type: :unique)
      ActiveGraph::Base.label_object(User.mapped_label_names.first).create_constraint(User.id_property_name, type: :unique)
      ActiveGraph::Base.label_object(Mention.mapped_label_names.first).create_constraint(Mention.id_property_name, type: :unique)
      ActiveGraph::Base.label_object(Namespace::TableX.mapped_label_names.first).create_constraint(Namespace::TableX.id_property_name, type: :unique)
      ActiveGraph::Base.label_object(Namespace::TableZ.mapped_label_names.first).create_constraint(Namespace::TableZ.id_property_name, type: :unique)

      Article.delete_all
      Category.delete_all
      Comment.delete_all
      User.delete_all
      Mention.delete_all
      (@ability = double).extend(CanCan::Ability)
    end

    it 'is for only neo4j classes' do
      expect(CanCan::ModelAdapters::ActiveGraphAdapter).to_not be_for_class(Object)
      expect(CanCan::ModelAdapters::ActiveGraphAdapter).to be_for_class(Article)
      expect(CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article))
        .to eq(CanCan::ModelAdapters::ActiveGraphAdapter)
    end

    it 'finds record' do
      article = Article.create!
      adapter = CanCan::ModelAdapters::AbstractAdapter.adapter_class(Article)
      expect(adapter.find(Article, article.id)).to eq(article)
    end

    it 'does not fetch any records when no abilities are defined' do
      Article.create!
      expect(Article.accessible_by(@ability)).to be_empty
    end

    it 'fetches all articles when one can read all' do
      @ability.can :read, Article
      article = Article.create!
      expect(Article.accessible_by(@ability).to_a).to eq([article])
      expect(@ability).to be_able_to(:read, article)
    end

    it 'fetches article with id in conditions' do
      article = Article.create!
      @ability.can :read, Article, id: article.id
      expect(Article.accessible_by(@ability).to_a).to eq([article])
      expect(@ability).to be_able_to(:read, article)
    end

    it 'fetches User with id when neo_id is id_property' do
      User.id_property(:neo_id)
      user = User.create!
      @ability.can :read, User, id: user.neo_id
      expect(User.accessible_by(@ability).to_a).to eq([user])
    end

    it 'fetches article with nil in attribute conditions' do
      article = Article.create!
      Article.create!(name: 'Chunky')
      @ability.can :read, Article, name: nil
      expect(Article.accessible_by(@ability).to_a).to eq([article])
      expect(@ability).to be_able_to(:read, article)
    end

    it 'fetches only the articles that are published' do
      @ability.can :read, Article, published: true
      article1 = Article.create!(published: true)
      article2 = Article.create!(published: false)
      expect(Article.accessible_by(@ability).to_a).to eq([article1])
      expect(@ability).to be_able_to(:read, article1)
      expect(@ability).not_to be_able_to(:read, article2)
    end

    it 'fetches any articles which are published or secret' do
      @ability.can :read, Article, published: true
      @ability.can :read, Article, secret: true
      article1 = Article.create!(published: true, secret: false)
      article2 = Article.create!(published: true, secret: true)
      article3 = Article.create!(published: false, secret: true)
      Article.create!(published: false, secret: false)
      expect(Article.accessible_by(@ability)).to contain_exactly(article1, article2, article3)
      expect(@ability).to be_able_to(:read, article1)
      expect(@ability).to be_able_to(:read, article2)
      expect(@ability).to be_able_to(:read, article3)
    end

    context 'nested rules' do
      before :each do
        @user = User.create!(name: 'Chunky')
        @cited = Article.create!(published: true)
        @article2 = Article.create!(published: true)
        @mention = Mention.create!(active: true)
        @mention.user = @user
        @cited.mentions << @mention
      end

      context 'single rule' do
        context 'can rules' do
          let(:accessible_article) { @article2 }
          let(:not_accessible_article) { @cited }
          context 'condition to check non existance of relation on base model' do
            before(:example) { @ability.can :read, Article, mentions: nil }
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on one level deep model' do
            before(:example) do
              @article2.mentions << Mention.create!
              @ability.can :read, Article, mentions: { user: nil }
            end
            include_context 'match expectations'
          end

          context 'nested condition with 1st relation being has one' do
            before(:example) do
              @article2.user = @user
              @ability.can :read, Article, user: { mentions: { id: @mention.id } }
            end
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on one level deep model with base model conditions' do
            before(:example) do
              @article2.mentions << Mention.create!
              @ability.can :read, Article, mentions: { user: nil }
            end
            include_context 'match expectations'
          end
        end

        context 'cannot rule' do
          let(:accessible_article) { @cited }
          let(:not_accessible_article) { @article2 }
          before(:example) { @ability.can :read, Article }

          context 'condition to check non existance of relation on base model' do
            before(:example) { @ability.cannot :read, Article, mentions: nil }
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on base model with base model conditions' do
            before(:example) do
              @ability.cannot :read, Article, mentions: nil
            end
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on one level deep model' do
            before(:example) do
              @article2.mentions << Mention.create!
              @ability.cannot :read, Article, mentions: { user: nil }
            end
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on one level deep model' do
            it 'fetches all articles with matching conditions' do
              @article2.mentions << Mention.create!
              @ability.cannot :read, Article, mentions: { user: nil }
              expect(Article.accessible_by(@ability)).to contain_exactly(@cited)
              expect(@ability).to be_able_to(:read, @cited)
            end
          end
        end
      end

      context 'with multiple rules' do
        context 'can rules' do
          let(:accessible_article) { @article2 }
          let(:not_accessible_article) { @cited }
          let(:rule_type) { :can }
          context 'condition to check non existance of relation on base model' do
            before(:example) do
              @ability.can :read, Article, mentions: nil
              @ability.can :manage, Article, published: false
            end
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on base model with base model conditions' do
            include_context 'rules with relation existance on base model'
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on one level deep model' do
            include_context 'rule with relation existance'
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on one level deep model with base model conditions' do
            include_context 'rules with relation existance on relation'
            include_context 'match expectations'
          end
        end

        context 'cannot rules' do
          let(:accessible_article) { @cited }
          let(:not_accessible_article) { @article2 }
          let(:rule_type) { :cannot }
          before(:example) { @ability.can :read, Article }
          context 'condition to check non existance of relation on base model' do
            before(:example) do
              @ability.cannot :manage, Article, published: false
              @ability.cannot :read, Article, mentions: nil
            end
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on base model with base model conditions' do
            include_context 'rules with relation existance on base model'
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on one level deep model' do
            include_context 'rule with relation existance'
            include_context 'match expectations'
          end

          context 'condition to check non existance of relation on one level deep model with base model conditions' do
            include_context 'rules with relation existance on relation'
            include_context 'match expectations'
          end
        end
      end

      context 'condition on relation attribute' do
        let(:accessible_article) { @cited }
        let(:not_accessible_article) { @article2 }
        context 'condition on 1st level deep model' do
          before(:example) do
            @ability.can :read, Article, mentions: { active: true }
            @ability.can :read, Article, published: false
          end
          include_context 'match expectations'
        end

        context 'condition on 2nd level deep model' do
          before(:example) do
            @ability.can :read, Article, mentions: { user: { name: 'Chunky' } }
            @ability.can :read, Article, published: false
          end
          include_context 'match expectations'
        end

        context 'condition on both 1st level and 2nd level deep model' do
          before(:example) do
            @ability.can :read, Article, mentions: { active: true,
                                                     user: { name: 'Chunky' } }
            @ability.can :read, Article, published: false
          end
          include_context 'match expectations'
        end

        context 'Combination of can and cannot rule' do
          before(:example) do
            @ability.can :read, Article, mentions: { active: true,
                                                     user: { name: 'Chunky' } }
            @ability.cannot :read, Article, published: false
          end
          include_context 'match expectations'
        end
      end
    end

    it 'fetches only the articles that are published and not secret' do
      @ability.can :read, Article, published: true
      @ability.cannot :read, Article, secret: true
      article1 = Article.create!(published: true, secret: false)
      Article.create!(published: true, secret: true)
      Article.create!(published: false, secret: true)
      Article.create!(published: false, secret: false)
      expect(Article.accessible_by(@ability).to_a).to eq([article1])
    end

    context 'multiple can rules with one rule without conditions' do
      it 'fetches all the articles' do
        @ability.can :read, Article, published: true
        @ability.can :read, Article
        article1 = Article.create!(published: true)
        article2 = Article.create!(published: false)
        expect(Article.accessible_by(@ability).to_a)
          .to contain_exactly(article1, article2)
      end
    end

    it 'only reads comments for articles which are published' do
      @ability.can :read, Comment, article: { published: true }
      comment1 = Comment.create!(article: Article.create!(published: true))
      Comment.create!(article: Article.create!(published: false))
      expect(Comment.accessible_by(@ability).to_a).to eq([comment1])
    end

    it 'should only read articles which are published with visible categories' do
      @ability.can :read, Article, published: true,
                                   category: { visible: true }
      Article.create!(published: true)
      Article.create!(published: false)
      article3 = Article.create!(published: true,
                                 category: Category.create!(visible: true))
      expect(Article.accessible_by(@ability).to_a).to eq([article3])
    end

    it 'should only read categories once even if they have multiple articles' do
      @ability.can :read, Category, articles: { published: true }
      @ability.can :read, Article, published: true
      category = Category.create!
      Article.create!(published: true, category: category)
      Article.create!(published: true, category: category)
      expect(Category.accessible_by(@ability).to_a).to eq([category])
    end

    it 'raises an exception when trying to merge scope with other conditions' do
      @ability.can :read, Article, published: true
      @ability.can :read, Article, Article.where(secret: true)
      message = 'Unable to merge an ActiveNode scope with other conditions. '\
                'Instead use a hash for read Article ability.'
      expect(-> { Article.accessible_by(@ability) })
        .to raise_error(CanCan::Error, message)
    end

    it 'allows a scope for conditions' do
      @ability.can :read, Article, Article.where(secret: true)
      article1 = Article.create!(secret: true)
      article2 = Article.create!(secret: false)
      expect(Article.accessible_by(@ability).to_a).to eq([article1])
      expect(@ability).to be_able_to(:read, article1)
      expect(@ability).not_to be_able_to(:read, article2)
    end

    it 'allows a AssociationProxy scope for conditions' do
      user = User.create!(name: 'Chunky')
      ability = Ability.new(user)
      ability.can :read, Article, user.articles
      article1 = Article.create!(user: user)
      article2 = Article.create!(secret: false)
      expect(Article.accessible_by(ability).to_a).to contain_exactly(article1)
      expect(ability).to be_able_to(:read, article1)
      expect(ability).not_to be_able_to(:read, article2)
    end

    it 'allows a scope for conditions with mupliple rules' do
      @ability.can :read, Article, Article.where(secret: true)
      @ability.can :read, Article
      article1 = Article.create!(secret: true)
      article2 = Article.create!(secret: false)
      expect(Article.accessible_by(@ability).to_a).to contain_exactly(article1, article2)
      expect(@ability).to be_able_to(:read, article1)
      expect(@ability).to be_able_to(:read, article2)
    end

    it 'only reads comments for visible categories through articles' do
      @ability.can :read, Comment, article: { category: { visible: true } }
      category1 = Category.create!(visible: true)
      comment1 = Comment.create!(article: Article.create!(category: category1))
      category2 = Category.create!(visible: false)
      Comment.create!(article: Article.create!(category: category2))
      expect(Comment.accessible_by(@ability)).to eq([comment1])
    end

    it 'does not allow to fetch records when ability with just block present' do
      @ability.can :read, Article do
        false
      end
      expect(-> { Article.accessible_by(@ability) }).to raise_error(CanCan::Error)
    end

    it 'should support more than one deeply nested conditions' do
      @ability.can :read, Comment, article: {
        category: {
          name: 'foo', visible: true
        }
      }
      expect { Comment.accessible_by(@ability) }.to_not raise_error
    end

    it 'should support deeply nested conditions with an Enumerable value' do
      @ability.can :read, Comment, article: { category: { name: ["Cars", "Sports"] } }

      category1 = Category.create!(name: "Cars", visible: true)
      category2 = Category.create!(name: "Sports", visible: true)
      category3 = Category.create!(name: "Books", visible: true)

      comment1 = Comment.create!(article: Article.create!(category: category1))
      comment2 = Comment.create!(article: Article.create!(category: category2))
      comment3 = Comment.create!(article: Article.create!(category: category3))

      expect(Comment.accessible_by(@ability)).to match_array([comment1, comment2])
      expect(@ability.can?(:read, comment1)).to be(true)
      expect(@ability.can?(:read, comment2)).to be(true)
      expect(@ability.can?(:read, comment3)).to be(false)
    end

    it 'returns empty set if no abilities match' do
      expect(@ability.model_adapter(Article, :read).database_records).to be_empty
    end

    it 'returns empty set for cannot clause' do
      @ability.cannot :read, Article
      expect(@ability.model_adapter(Article, :read).database_records).to be_empty
    end

    it 'returns cypher for single `can` rule and default `cannot` rule' do
      Article.create!(published: false, secret: true)
      @ability.cannot :read, Article
      @ability.can :read, Article, published: false, secret: true
      cypher_string = 'WHERE NOT(false)'
      expect(@ability.model_adapter(Article, :read).database_records.to_cypher)
        .to include(cypher_string)
    end

    it 'returns `false condition` for single `cannot` definition in front of default `cannot` condition' do
      @ability.cannot :read, Article
      @ability.cannot :read, Article, published: false, secret: true
      expect(@ability.model_adapter(Article, :read).database_records.to_cypher)
        .to include('(false)')
    end

    it 'returns `not (condition)` for single `cannot` definition in front of default `can` condition' do
      @ability.can :read, Article
      @ability.cannot :read, Article, published: false, secret: true
      str = 'OPTIONAL MATCH (article_1:`Article`) WITH '\
            'collect(DISTINCT article_1) as article_1_col UNWIND article_1_col'\
            ' as article_2 WITH DISTINCT article_2 as article_2 MATCH '\
            '(article_2) WHERE NOT(article_2.published = $article_2_published'\
            ' AND article_2.secret = $article_2_secret) WITH '\
            'collect(DISTINCT article_2) as article_2_col UNWIND article_2_col'\
            ' as article_can WITH DISTINCT article_can as article'
      expect(@ability.model_adapter(Article, :read).database_records.to_cypher)
        .to include(str)
    end

    it 'merges :all conditions with other conditions' do
      user = User.create!(name: 'Chunky')
      article = Article.create!(user: user)
      ability = Ability.new(user)
      ability.can :manage, :all
      ability.can :manage, Article, user: { name: user.name }
      expect(Article.accessible_by(ability)).to eq([article])
    end

    it 'should not execute a scope when checking ability on the class' do
      relation = Article.where(secret: true)
      @ability.can :read, Article, relation do |article|
        article.secret == true
      end

      allow(relation).to receive(:count).and_raise('Unexpected scope execution.')

      expect { @ability.can? :read, Article }.not_to raise_error
    end

    it 'returns appropriate sql conditions in complex case' do
      Article.create!(name: 'Chunky', secret: false)
      @ability.can :read, Article
      @ability.can :manage, Article, name: 'Chunky'
      @ability.can :update, Article, published: true
      @ability.cannot :update, Article, secret: true
      cypher_string = 'WHERE (article_1.name = $article_1_name)'
      subject1 = @ability.model_adapter(Article, :update)
                         .database_records.to_cypher
      expect(subject1).to include(cypher_string)
      subject2 = @ability.model_adapter(Article, :manage)
                         .database_records.to_cypher
      expect(subject2).to include('(article.name =')
      subject3 = @ability.model_adapter(Article, :read)
                         .database_records.to_cypher_with_params
      expect(subject3).to include('MATCH (n:`Article`) RETURN n')
    end

    context 'with namespaced models' do
      it 'fetches all namespace::table_x when one is related by table_y' do
        user = User.create!(name: 'Chunky')
        ability = Ability.new(user)
        conditions = { table_zs: { user: { name: 'Chunky' } } }
        ability.can :read, Namespace::TableX, conditions
        table_x = Namespace::TableX.create!
        table_z = Namespace::TableZ.create(user: user)
        table_x.table_zs << table_z
        expect(Namespace::TableX.accessible_by(ability)).to eq([table_x])
      end
    end

    context 'condition with variable length relation' do
      it 'fetches all variable length realtion nodes with conditions' do
        active_user = User.create!(name: 'Chunky-2', status: 'active')
        inactive_user = User.create!(name: 'Chunky-1', friends: [active_user])
        user = User.create!(name: 'Chunky', friends: [inactive_user])
        ability = Ability.new(user)
        ability.can :read, User, friends: { status: 'active',
                                            rel_length: { min: 0 } }
        expect(User.accessible_by(ability)).to contain_exactly(
          user, inactive_user, active_user
        )
        expect(ability).to be_able_to(:read, user)
      end

      it 'fetches all variable length realtion nodes with nested relation conditions' do
        active_user = User.create!(name: 'Chunky-2', status: 'active')
        inactive_user = User.create!(name: 'Chunky-1', friends: [active_user])
        user = User.create!(name: 'Chunky', friends: [inactive_user])
        active_user.articles = [Article.create!(published: true)]
        ability = Ability.new(user)
        ability.can :read, User, friends: { rel_length: { min: 0 },
                                            articles: { published: true } }
        expect(User.accessible_by(ability)).to contain_exactly(
          user, inactive_user, active_user
        )
        expect(ability).to be_able_to(:read, active_user)
      end
    end

    context 'condition on association' do
      it 'constructs correct cypher with association node lable' do
        @ability.can :read, Article, mentions: { user: nil }
        expect(Article.accessible_by(@ability).to_cypher).to include(
          'MATCH (article:`Article`) WHERE'\
          ' (NOT (article:`Article`)-[:`mention`]->(:`Mention`)-[:`user`]->'\
          '(:`User`))'
        )
      end
    end

    it 'does not fire query on rule with scope for only_block?' do
      start_count = $expect_queries_count
      @ability.can :read, Article, Article.where(published: true)
      @ability.instance_variable_get(:@rules).first.only_block?
      expect($expect_queries_count - start_count).to eq(0)
    end
  end
end
