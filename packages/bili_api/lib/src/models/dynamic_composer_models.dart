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

final class ApiDynamicContent {
  const ApiDynamicContent(this.text, this.type, {this.id = ''});
  final String text, id;
  final int type;
}

final class ApiDynamicMention {
  const ApiDynamicMention(this.id, this.name, this.avatar);
  final String id, name;
  final Uri? avatar;
}

final class ApiDynamicPollOption {
  const ApiDynamicPollOption(this.text, {this.imageUrl});
  final String text;
  final Uri? imageUrl;
}
