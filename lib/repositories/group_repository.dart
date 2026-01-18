import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_group.dart';

class GroupRepository {
  final CollectionReference _groupsCollection =
      FirebaseFirestore.instance.collection('community_groups');

  Stream<List<CommunityGroup>> getGroupsStream() {
    return _groupsCollection.orderBy('sortOrder').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => CommunityGroup.fromFirestore(doc)).toList();
    });
  }

  Future<void> addGroup(CommunityGroup group) async {
    await _groupsCollection.add(group.toMap());
  }

  Future<void> updateGroup(CommunityGroup group) async {
    await _groupsCollection.doc(group.id).update(group.toMap());
  }

  Future<void> deleteGroup(String groupId) async {
    await _groupsCollection.doc(groupId).delete();
  }
}
