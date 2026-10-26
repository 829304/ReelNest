import 'package:flutter/material.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../domain/tmdb_models.dart';

class TmdbDetailExtras extends StatefulWidget {
  const TmdbDetailExtras({required this.metadata, super.key});

  final TmdbMetadata metadata;

  @override
  State<TmdbDetailExtras> createState() => _TmdbDetailExtrasState();
}

class _TmdbDetailExtrasState extends State<TmdbDetailExtras> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final metadata = widget.metadata;
    if (metadata.crew.isEmpty && metadata.cast.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      key: const ValueKey('tmdb-movie-detail-extras'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          key: const ValueKey('toggle-tmdb-details'),
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: Row(
            children: [
              AnimatedRotation(
                turns: _expanded ? .25 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: const Icon(Icons.chevron_right_rounded, size: 17),
              ),
              const SizedBox(width: 10),
              const Text(
                '详情',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 14),
          if (metadata.crew.isNotEmpty)
            _PeopleSection(
              title: '主创',
              icon: Icons.person_outline_rounded,
              people: metadata.crew,
            ),
          if (metadata.cast.isNotEmpty)
            _PeopleSection(
              title: '演员',
              icon: Icons.people_outline_rounded,
              people: metadata.cast,
            ),
        ],
      ],
    );
  }
}

/// Compatibility wrapper for existing movie-only presentation tests.
class TmdbMovieDetailExtras extends TmdbDetailExtras {
  const TmdbMovieDetailExtras({required super.metadata, super.key});
}

class _PeopleSection extends StatelessWidget {
  const _PeopleSection({
    required this.title,
    required this.icon,
    required this.people,
  });

  final String title;
  final IconData icon;
  final List<TmdbPerson> people;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: palette.menuText),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  key: ValueKey('tmdb-${title == '主创' ? 'crew' : 'cast'}'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 4,
                  ),
                  itemCount: people.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (_, index) =>
                      _PersonCard(person: people[index], palette: palette),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.palette});

  final TmdbPerson person;
  final SourceSheetPalette palette;

  @override
  Widget build(BuildContext context) {
    final url = person.profileUrl;
    final placeholder = ColoredBox(
      color: palette.control,
      child: Icon(Icons.person_rounded, color: palette.secondary, size: 30),
    );
    return SizedBox(
      key: ValueKey('tmdb-person-${person.id}-${person.role}'),
      width: 88,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox.square(
              dimension: 72,
              child: url == null || url.isEmpty
                  ? placeholder
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => placeholder,
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            person.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            person.role,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: palette.secondary),
          ),
        ],
      ),
    );
  }
}
