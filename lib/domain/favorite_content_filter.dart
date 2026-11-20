enum FavoriteContentOrder { recentlySaved, mostPlayed, recentlyPublished }

typedef FavoriteContentFilter = ({
  String keyword,
  FavoriteContentOrder order,
  bool allFolders,
});

const defaultFavoriteContentFilter = (
  keyword: '',
  order: FavoriteContentOrder.recentlySaved,
  allFolders: false,
);

extension FavoriteContentScope on FavoriteContentFilter {
  bool get searchesAllFolders => allFolders && keyword.isNotEmpty;
}
