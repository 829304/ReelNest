import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/platform/directory_safety.dart';

void main() {
  const info = '21 1 8:17 / /mnt/Media rw - ext4 /dev/sdb1 rw';
  const path = '/mnt/Media/Film.mkv';
  Future<String?> probe({
    String? uuid = 'volume-a',
    LinuxVolumeUuidLookup? lookup,
    Future<String> Function()? read,
  }) => linuxDirectoryIdentity(
    path,
    readMountInfo: read ?? () async => info,
    volumeUuid: lookup ?? (_) async => uuid,
  );

  test(
    'same mounted volume has stable identity and UUID replacement differs',
    () async {
      final first = await probe();
      expect(first, isNotNull);
      expect(await probe(), first);
      expect(await probe(uuid: 'volume-b'), isNot(first));
      expect(await probe(uuid: null), isNull);
      expect(await probe(uuid: '  '), isNull);
      // A normal remount with a different Linux device name is the same volume.
      expect(
        await probe(
          read: () async => '34 1 8:33 / /mnt/Media rw - ext4 /dev/sdc1 rw',
        ),
        first,
      );
    },
  );

  test(
    'mount changes during lookup and UUID changes between probes are unknown',
    () async {
      var reads = 0;
      expect(
        await probe(
          read: () async => reads++ == 0
              ? info
              : '22 1 8:17 / /mnt/Media rw - ext4 /dev/sdb1 rw',
        ),
        isNull,
      );
      var calls = 0;
      expect(
        await probe(
          lookup: (_) async => calls++ == 0 ? 'volume-a' : 'volume-b',
        ),
        isNull,
      );
      expect(
        await probe(lookup: (_) async => throw Exception('probe denied')),
        isNull,
      );
      expect(await probe(read: () async => ''), isNull);
    },
  );

  test(
    'UUID lookup uses device number and requires a unique nonempty UUID',
    () async {
      const output =
          '{"blockdevices":['
          '{"name":"/dev/sda1","maj:min":"8:1","uuid":"wrong"},'
          '{"name":"/dev/sdb1","maj:min":"8:17","uuid":"ABCD-1234"}]}';
      expect(
        await probe(
          lookup: (mount) async => linuxVolumeUuidFromLsblk(mount, output),
        ),
        contains('abcd-1234'),
      );
      for (final invalid in [
        '{"blockdevices":[{"name":"/dev/sdb1","maj:min":"8:18","uuid":"a"}]}',
        '{"blockdevices":[{"maj:min":"8:17","uuid":null}]}',
        '{"blockdevices":[{"maj:min":"8:17","uuid":"a"},{"maj:min":"8:17","uuid":"b"}]}',
        '{"blockdevices":[]}',
        'not-json',
      ]) {
        expect(
          await probe(
            lookup: (mount) async => linuxVolumeUuidFromLsblk(mount, invalid),
          ),
          isNull,
        );
      }
    },
  );

  test('virtual device number resolves the mounted block source, not a different disk', () async {
    const virtualInfo = '21 1 0:42 / /mnt/Media rw - btrfs /dev/sdb1 rw';
    const output =
        '{"blockdevices":['
        '{"name":"/dev/sda1","maj:min":"8:1","uuid":"wrong"},'
        '{"name":"/dev/sdb1","maj:min":"8:17","uuid":"volume-a"}]}';
    expect(
      await probe(
        read: () async => virtualInfo,
        lookup: (mount) async => linuxVolumeUuidFromLsblk(mount, output),
      ),
      contains('volume-a'),
    );
  });

  test('unknown nested mount never falls back to the known parent volume', () {
    const nested =
        '$info\n22 21 8:33 / /mnt/Media/nested rw - ext4 /dev/sdc1 rw';
    expect(
      linuxMountIdentity(
        '/mnt/Media/nested/Film.mkv',
        nested,
        volumeUuids: {'8:17': 'volume-a'},
      ),
      isNull,
    );
    expect(
      linuxMountIdentity(
        '/mnt/Media/Film.mkv',
        nested,
        volumeUuids: {'8:17': 'volume-a'},
      ),
      isNotNull,
    );
  });

  test(
    'network shares keep their own identity without a block UUID probe',
    () async {
      const network =
          '21 1 0:42 / /mnt/Media rw - cifs //user:secret@nas/Media rw';
      final identity = await probe(
        read: () async => network,
        lookup: (_) async =>
            throw StateError('Network share must not query lsblk'),
      );
      expect(identity, contains('//nas/Media'));
      expect(identity, isNot(contains('secret')));
      expect(
        await probe(
          read: () async => network.replaceAll('/Media rw', '/Other rw'),
        ),
        isNot(identity),
      );
    },
  );
}
