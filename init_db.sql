-- SmartOutfit: PostgreSQL DDL
-- ファイル: init_db.sql
-- 用途: SmartOutfit バックエンド用の初期データベース定義（テーブル作成）
-- 注意: この SQL は id のデフォルト値に gen_random_uuid() を使います。
--       事前に pgcrypto 拡張を有効化してください。

/*
プロジェクト構成図（Backend / iOSを分離）

SmartOutfit/
├─ backend/                 -- FastAPI backend
│  ├─ app/
│  │  ├─ main.py
│  │  ├─ api/
│  │  ├─ models/
│  │  ├─ services/
│  │  └─ db/
│  │     └─ migrations/
│  ├─ requirements.txt
│  └─ Dockerfile
└─ ios/                     -- iOS (SwiftUI)
   ├─ SmartOutfit.xcodeproj
   ├─ SmartOutfit/
   │  ├─ App.swift
   │  ├─ Views/
   │  └─ Models/
   └─ README.md

この SQL は backend 側の `db/migrations` に配置する `init_db.sql` を想定しています。
*/

-- 拡張: UUID 生成用の関数を利用
-- pgcrypto の gen_random_uuid() を使用するため、有効化します。
-- (Postgres 管理者権限で実行してください)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ステータス列用の ENUM 型
CREATE TYPE IF NOT EXISTS outfit_status AS ENUM ('ACTIVE', 'LAUNDRY', 'DISCARDED');

-- users テーブル
CREATE TABLE IF NOT EXISTS users (
  user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- 洗濯間隔（日数）。この期間内に着用された服は提案から除外するロジック用
  wash_cycle_days INTEGER NOT NULL DEFAULT 3 CHECK (wash_cycle_days > 0),
  -- 将来拡張用: ここではユーザー名やメールはアプリ側で別に管理する想定
  -- 必要に応じてカラムを追加してください
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- 行の最終更新時刻。アプリ/DB トリガーで更新する想定
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE users IS 'ユーザー情報。wash_cycle_days により提案から除外する着用期間を制御する。';
COMMENT ON COLUMN users.wash_cycle_days IS '洗濯頻度（日）。この日数以内に着た服は提案しない。デフォルト3。';

-- clothes テーブル
CREATE TABLE IF NOT EXISTS clothes (
  cloth_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  image_url TEXT NOT NULL,
  category TEXT NOT NULL,
  features JSONB NOT NULL,
  status outfit_status NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- 論理削除時刻（status = 'DISCARDED' のときにセットする）
  deleted_at TIMESTAMPTZ DEFAULT NULL,
  -- 行の最終更新時刻
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT fk_clothes_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

COMMENT ON TABLE clothes IS 'ユーザーが登録した服のメタ情報。AI判定用特徴は JSONB に格納。';
COMMENT ON COLUMN clothes.image_url IS '画像パスまたは CDN URL。アプリではこの URL を参照して表示する。';
COMMENT ON COLUMN clothes.category IS 'カテゴリ（例: トップス, ボトムス, アウター 等）。アプリで分類して表示するための文字列。';
COMMENT ON COLUMN clothes.features IS $$
JSONB で保存する AI 用特徴データの想定構造:
{
  "color": "白",
  "pattern": "無地",
  "material": "ウール",
  "warmth_level": 3,           -- 1(薄い)〜5(暖かい)
  "is_rain_ok": true,          -- 雨の日に着用可能か
  "seasons": ["春","冬"]   -- 該当シーズンの配列
}
-- アプリ/バックエンド側でこの構造を尊重して検索・判定を行う。
$$;
COMMENT ON COLUMN clothes.status IS '服の状態。ACTIVE(利用可能) / LAUNDRY(洗濯中) / DISCARDED(廃棄)';

-- worn_history テーブル
CREATE TABLE IF NOT EXISTS worn_history (
  history_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cloth_id UUID NOT NULL,
  worn_date DATE NOT NULL,
  CONSTRAINT fk_history_cloth FOREIGN KEY (cloth_id) REFERENCES clothes(cloth_id) ON DELETE CASCADE,
  -- 最終更新時刻
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE worn_history IS '服の着用履歴。wash_cycle に基づく提案除外判定の根拠となる。';
COMMENT ON COLUMN worn_history.worn_date IS '着用日（DATE）。この日付から wash_cycle_days を計算して提案除外する。';

-- インデックス: 検索でよく使う列に対して
CREATE INDEX IF NOT EXISTS idx_clothes_user_id ON clothes(user_id);
CREATE INDEX IF NOT EXISTS idx_worn_history_cloth_id ON worn_history(cloth_id);
CREATE INDEX IF NOT EXISTS idx_worn_history_worn_date ON worn_history(worn_date);

-- JSONB 検索向けインデックス: features の GIN インデックスは部分一致や包含検索を高速化します
CREATE INDEX IF NOT EXISTS idx_clothes_features_gin ON clothes USING GIN (features);

-- 機能的インデックス: warmth_level に対する数値比較が頻繁に行われる場合に有効
-- 注意: features->>'warmth_level' が常に整数文字列であることを保証してください（アプリ側バリデーション推奨）
CREATE INDEX IF NOT EXISTS idx_clothes_warmth_level ON clothes ( ((features->>'warmth_level')::int) );

-- 追加テーブル: 外部認証プロバイダとユーザーIDの紐付け
-- 1人のユーザーが複数プロバイダ（Firebase, Apple など）を持つ可能性を考慮
CREATE TABLE IF NOT EXISTS user_auth_providers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  provider_user_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_provider_user UNIQUE (provider, provider_user_id)
);

COMMENT ON TABLE user_auth_providers IS '外部認証プロバイダ（Firebase, Apple 等）のユーザーID を保存する。';
COMMENT ON COLUMN user_auth_providers.provider IS '例: "firebase", "apple"';
COMMENT ON COLUMN user_auth_providers.provider_user_id IS '外部プロバイダが返す一意のユーザーID（UID）。プロバイダごとにユニーク。';

-- トリガー: updated_at を自動更新する汎用関数とトリガー
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_set_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_clothes_set_updated_at BEFORE UPDATE ON clothes FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_worn_history_set_updated_at BEFORE UPDATE ON worn_history FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_user_auth_providers_set_updated_at BEFORE UPDATE ON user_auth_providers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 利便性: 各テーブルの最終更新などを取得する簡易ビュー（任意）
-- CREATE OR REPLACE VIEW vw_user_clothes_count AS
-- SELECT u.user_id, count(c.cloth_id) as clothes_count
-- FROM users u LEFT JOIN clothes c ON u.user_id = c.user_id
-- GROUP BY u.user_id;

-- 使用例（コメント）:
-- 1) あるユーザーの、wash_cycle_days 期間内に着られた服を除外して候補を取得するクエリ例
--    SELECT c.*
--    FROM clothes c
--    JOIN users u ON c.user_id = u.user_id
--    WHERE c.user_id = '<ユーザーUUID>'
--      AND c.status = 'ACTIVE'
--      AND NOT EXISTS (
--        SELECT 1 FROM worn_history w
--        WHERE w.cloth_id = c.cloth_id
--          AND w.worn_date >= (current_date - u.wash_cycle_days)
--      );

-- 注意事項:
-- - features の JSONB についてはバックエンド側でスキーマバリデーション（例: pydantic）を行ってください。
-- - 必要に応じて clothes.category を ENUM にしても良いですが、将来的な拡張性を考慮して TEXT にしています。
-- - 大量データが発生する場合、worn_history をパーティショニング（日付ベース）することを検討してください。

-- EOF
