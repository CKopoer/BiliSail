final class ApiDynamicComposeTopic {
  const ApiDynamicComposeTopic(this.id, this.name);
  final String id, name;
}

final class ApiDynamicPicture {
  const ApiDynamicPicture(this.url, this.width, this.height, this.sizeKiB);
  final Uri url;
  final int width, height;
  final double sizeKiB;
}
