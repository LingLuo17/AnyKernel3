const path = require('path');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');

module.exports = {
  // 入口：ES Module 主文件（内部导入了 SCSS）
  entry: './js/main.js',

  output: {
    filename: 'app.bundle.js',
    path: path.resolve(__dirname, 'dist'),
    clean: true,
  },

  module: {
    rules: [
      {
        // 处理 SCSS 文件：sass-loader → css-loader → 提取为独立 CSS 文件
        test: /\.scss$/,
        use: [
          MiniCssExtractPlugin.loader,
          'css-loader',
          'sass-loader',
        ],
      },
    ],
  },

  plugins: [
    new MiniCssExtractPlugin({
      filename: 'style.bundle.css',
    }),
  ],

  // 生产模式自动启用 terser 压缩 JS + CSS
  optimization: {
    minimize: true,
  },
};
